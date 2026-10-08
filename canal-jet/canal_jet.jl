# # Barotropic instability of a zonal jet: Oceananigans replica of NEMO's CANAL test case
#
# Reproduces NEMO 4.2's `tests/CANAL` configuration with `nn_initcase = 1` (geostrophic zonal jet)
# on the same grid and initial condition, but with 9th-order WENO advection and no turbulence closure:
#
# * f-plane at 38.5ᵒN, flat bottom, 1000 m deep, single vertical level,
# * 5 km grid: 401 cells periodic in x (2005 km), 199 ocean cells between walls in y (995 km),
# * 1 m s⁻¹ top-hat jet over |y| ≤ 200 km, in geostrophic balance with the free surface,
# * free surface perturbed by uniform random noise in [-5, 5] cm to seed the instability,
# * salinity 35 inside the jet and 30 outside, advected as a passive dye (no buoyancy).
#
# Surface salinity, vertical vorticity, and free-surface displacement are saved every 6 hours
# to `canal_jet_oceananigans.jld2`. Run with `julia --project canal_jet.jl`.

using Oceananigans
using Oceananigans.Units
using JLD2
using Printf
using Random

arch = CPU()

# NEMO places T-points at x = -1000, -995, ..., 1000 km (periodic) and y = -500, ..., 500 km,
# with land on the first and last rows. Cell faces sit halfway between T-points.
Δ = 5kilometers
Nx = 401
Ny = 199
H = 1000meters

grid = RectilinearGrid(arch; size = (Nx, Ny, 1), halo = (5, 5, 5),
                       x = (-Nx * Δ / 2, Nx * Δ / 2),
                       y = (-Ny * Δ / 2, Ny * Δ / 2),
                       z = (-H, 0),
                       topology = (Periodic, Bounded, Bounded))

coriolis = FPlane(latitude = 38.5)

# With 60 substeps per 10-minute step, the barotropic CFL number √(gH) Δt / 60Δ is ≈ 0.2.
free_surface = SplitExplicitFreeSurface(grid; substeps = 60)

model = HydrostaticFreeSurfaceModel(grid;
                                    coriolis,
                                    free_surface,
                                    momentum_advection = WENO(order = 9),
                                    tracer_advection = WENO(order = 9),
                                    closure = nothing,
                                    buoyancy = nothing,
                                    tracers = :S)

# ## Initial condition (NEMO `usrdef_istate.F90`, case 1)

U = 1     # m s⁻¹
ℓ = 200kilometers
g = model.free_surface.gravitational_acceleration
f = coriolis.f

in_jet(y) = abs(y) ≤ ℓ + Δ / 4 # includes the T-points at y = ±200 km, as in NEMO

uᵢ(x, y, z) = in_jet(y) ? U : 0
Sᵢ(x, y, z) = in_jet(y) ? 35 : 30

Random.seed!(1234)
ηᵢ(x, y, z) = - f * U * clamp(y, -ℓ, ℓ) / g + 0.1 * rand() - 0.05

set!(model, u = uᵢ, S = Sᵢ, η = ηᵢ)

# ## Simulation

simulation = Simulation(model, Δt = 10minutes, stop_time = 60days)

wall_clock = Ref(time_ns())

function progress(sim)
    u, v, w = sim.model.velocities
    elapsed = 1e-9 * (time_ns() - wall_clock[])
    @info @sprintf("iter %5d, t = %6.2f days, max|u| = %.3f m s⁻¹, max|v| = %.3f m s⁻¹, wall time = %s",
                   iteration(sim), time(sim) / day, maximum(abs, u), maximum(abs, v), prettytime(elapsed))
    wall_clock[] = time_ns()
    return nothing
end

add_callback!(simulation, progress, IterationInterval(720))

u, v, w = model.velocities
ζ = ∂x(v) - ∂y(u)
S = model.tracers.S
η = model.free_surface.displacement

simulation.output_writers[:fields] = JLD2Writer(model, (; S, ζ, η);
                                                filename = "canal_jet_oceananigans.jld2",
                                                schedule = TimeInterval(6hours),
                                                overwrite_files = true)

run!(simulation)
