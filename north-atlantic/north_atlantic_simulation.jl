# # A quarter-degree North Atlantic simulation
#
# A cheap, regional North Atlantic configuration built with Oceananigans and NumericalEarth:
#
# * 1/4° latitude-longitude grid with 4 vertical layers,
# * initialized from the GLORYS 1/12° daily reanalysis,
# * temperature and salinity restored to ECCO4 in sponge layers along the open boundaries,
# * forced by the JRA55-do repeat-year atmosphere through similarity-theory bulk formulae.
#
# Surface fields are saved every 12 hours to `north_atlantic_surface.jld2`.
# Run with `julia --project north_atlantic_simulation.jl`.
# GLORYS downloads require Copernicus Marine credentials in
# `COPERNICUSMARINE_SERVICE_USERNAME` and `COPERNICUSMARINE_SERVICE_PASSWORD`;
# ECCO downloads require `ECCO_USERNAME` and `ECCO_WEBDAV_PASSWORD`.

using NumericalEarth
using NumericalEarth.DataWrangling: BoundingBox
using Oceananigans
using Oceananigans.Units
using Oceananigans.OutputReaders: Clamp
using CopernicusMarine
using Dates: DateTime, Month
using Printf

arch = CPU()

# Workaround for a NumericalEarth bug: `remaining_gaps` counts NaNs with a Float32 sum,
# which saturates at 2²⁴ ≈ 1.7×10⁷. The GLORYS subset for this domain has ~2.7×10⁷ land
# cells, so inpainting stops after one pass and fills the remaining gaps with zeros.
# Counting with integers lets inpainting run to completion.
import NumericalEarth.DataWrangling: remaining_gaps
remaining_gaps(field, mask) = count(interior(mask) .& isnan.(interior(field)))

# ## Grid and bathymetry
#
# The domain spans the Gulf of Mexico to Scandinavia and the tropics to the Nordic Seas.

const λw, λe = -100, 15 # longitude
const φs, φn =    5, 70 # latitude

Nx = 4 * (λe - λw)
Ny = 4 * (φn - φs)

# Four layers that thicken with depth.
z = [-5000, -2000, -600, -100, 0]
Nz = length(z) - 1

underlying_grid = LatitudeLongitudeGrid(arch;
                                        size = (Nx, Ny, Nz),
                                        longitude = (λw, λe),
                                        latitude = (φs, φn),
                                        z,
                                        halo = (7, 7, 7))

# Keeping only the largest connected basin discards the slice of the eastern Pacific
# in the southwest corner of the domain.
bottom_height = regrid_bathymetry(underlying_grid;
                                  minimum_depth = 10,
                                  interpolation_passes = 5,
                                  major_basins = 1)

grid = ImmersedBoundaryGrid(underlying_grid, GridFittedBottom(bottom_height); active_cells_map = true)

# ## Boundary restoring to ECCO
#
# The mask is 1 at the domain edges and decays linearly to 0 over `sponge_width` degrees.

const sponge_width = 3 # degrees

@inline function boundary_mask(λ, φ, z, t)
    west  = (λw + sponge_width - λ) / sponge_width
    east  = (λ - λe + sponge_width) / sponge_width
    south = (φs + sponge_width - φ) / sponge_width
    north = (φ - φn + sponge_width) / sponge_width
    return clamp(max(west, east, south, north), 0, 1)
end

start_date = DateTime(1993, 1, 1)
stop_date  = DateTime(1993, 4, 1)

# ECCO4 monthly fields bracketing the run, with one extra month for time interpolation.
restoring_kw = (; dataset = ECCO4Monthly(), start_date, end_date = stop_date + Month(1))
restoring_rate = 1 / 5days

FT = DatasetRestoring(Metadata(:temperature; restoring_kw...), arch;
                      rate = restoring_rate, mask = boundary_mask, time_indexing = Clamp())

FS = DatasetRestoring(Metadata(:salinity; restoring_kw...), arch;
                      rate = restoring_rate, mask = boundary_mask, time_indexing = Clamp())

# ## Ocean simulation

ocean = ocean_simulation(grid; forcing = (T = FT, S = FS))

# ## Initial conditions from GLORYS
#
# We download only the GLORYS subset covering the domain.

glorys_region = BoundingBox(longitude = (λw, λe), latitude = (φs, φn))
glorys(name) = Metadatum(name; dataset = GLORYSDaily(), date = start_date, region = glorys_region)

set!(ocean.model,
     T = glorys(:temperature),
     S = glorys(:salinity),
     u = glorys(:u_velocity),
     v = glorys(:v_velocity))

# ## Atmospheric forcing
#
# JRA55-do repeat-year forcing. Without a sea ice model, ocean temperature is
# limited to the freezing point.

atmosphere = JRA55PrescribedAtmosphere(arch)
radiation  = JRA55PrescribedRadiation(arch)

coupled_model = OceanSeaIceModel(ocean, FreezingLimitedOceanTemperature(); atmosphere, radiation)

# Start with a short step while the GLORYS state adjusts to the coarse vertical grid
# and the regridded bathymetry, then increase it.
simulation = Simulation(coupled_model; Δt = 2minutes, stop_time = 2days)

wall_clock = Ref(time_ns())

function progress(sim)
    u, v, w = sim.model.ocean.model.velocities
    T = sim.model.ocean.model.tracers.T
    elapsed = 1e-9 * (time_ns() - wall_clock[])

    @info @sprintf("%s, iter: %d, Δt: %s, max|u|: (%.2f, %.2f, %.1e) m s⁻¹, extrema(T): (%.1f, %.1f) ᵒC, wall: %s",
                   prettytime(sim), iteration(sim), prettytime(sim.Δt),
                   maximum(abs, u), maximum(abs, v), maximum(abs, w),
                   minimum(T), maximum(T), prettytime(elapsed))

    wall_clock[] = time_ns()
    return nothing
end

add_callback!(simulation, progress, TimeInterval(1day))

# ## Output

u, v, w = ocean.model.velocities
speed = sqrt(u^2 + v^2)
outputs = merge(ocean.model.velocities, ocean.model.tracers, (; speed))

ocean.output_writers[:surface] = JLD2Writer(ocean.model, outputs;
                                            schedule = TimeInterval(12hours),
                                            filename = "north_atlantic_surface",
                                            indices = (:, :, Nz),
                                            overwrite_files = true)

# ## Run

run!(simulation)

simulation.Δt = 10minutes
simulation.stop_time = (stop_date - start_date).value / 1000 # seconds
run!(simulation)
