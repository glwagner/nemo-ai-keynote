"""Barotropic instability of a zonal jet: legoESM replica of NEMO's CANAL test case.

Same grid, initial condition, and output as `canal_jet.jl` (Oceananigans), using the legoESM
lat-lon C-grid ocean on its Cartesian f-plane geometry, configured to mirror the Oceananigans run:

* f-plane at 38.5ᵒN, flat bottom, 1000 m deep, one level, linear free surface,
* 5 km grid: 401 cells periodic in x (2005 km), 199 cells between free-slip walls in y (995 km),
* 1 m s⁻¹ top-hat jet over |y| ≤ 200 km in geostrophic balance, plus uniform random
  free-surface noise in [-5, 5] cm; salinity 35 inside the jet and 30 outside, passive (linear EOS
  with zero thermal and haline expansion),
* WENO9 vector-invariant momentum advection (legoESM's "W9V" preset with Oceananigans' default
  self-upwinded divergence smoothness), WENO7 tracer advection
  (legoESM has no WENO9 tracer scheme), no lateral or vertical viscosity/diffusion, no bottom drag,
* split-explicit free surface (60 substeps), AB2 outer and tracer time stepping, Δt = 10 min.

Surface salinity, vertical vorticity, and free-surface displacement are saved every 6 hours to
`canal_jet_legoesm.nc`. Run from a legoESM checkout's environment:

    JAX_PLATFORMS=cpu JAX_ENABLE_X64=1 /path/to/legoESM/.venv/bin/python canal_jet_legoesm.py [stop_days]
"""
import os
import sys
import time

os.environ.setdefault("JAX_ENABLE_X64", "1")
os.environ.setdefault("JAX_PLATFORMS", "cpu")

import jax
import jax.numpy as jnp
import numpy as np
from netCDF4 import Dataset

from legoesm import constants
from legoesm.core.precision import PrecisionPolicy, set_policy

set_policy(PrecisionPolicy.fp64())   # the default policy is fp32; set before building grid and state

from legoesm.grids.latlon import create_beta_plane_cgrid_geometry
from legoesm.ocean.dynamics.ocean_model_latlon_cgrid import LatLonCGridOceanModel
from legoesm.ocean.eos import LinearEOSConfig
from legoesm.ocean.experiments.silvestri_schemes import apply_silvestri_scheme
from legoesm.ocean.fidelity.oceananigans_recipe import oceananigans_canonical_ocean_config
from legoesm.ocean.init_latlon_cgrid import rest_state_latlon_cgrid_ocean
from legoesm.ocean.vertical import create_ocean_z_star

stop_days = float(sys.argv[1]) if len(sys.argv) > 1 else 60.0
output = os.environ.get("CANAL_OUTPUT", "canal_jet_legoesm.nc")

# Grid matching NEMO's T-points: x = -1000, ..., 1000 km and y = -495, ..., 495 km.
Δ = 5e3
Nx, Ny = 401, 199
H = 1000.0
g = 9.80665                       # Oceananigans' default
f0 = 2 * constants.Omega * np.sin(np.radians(38.5))

grid = create_beta_plane_cgrid_geometry(Ny, Nx, dx_m=Δ, dy_m=Δ, f0=f0, beta=0.0,
                                        y_origin_m=-Ny * Δ / 2, x_origin_m=-Nx * Δ / 2,
                                        cartesian_pseudo_lat=True)
z = create_ocean_z_star(n_levels=1, H_max=H)._replace(linear_free_surface=True)

config = oceananigans_canonical_ocean_config(
    eos_linear=LinearEOSConfig(alpha_T=0.0, beta_S=0.0),
    g=g, A_h=0.0, K_h=0.0, A_v=0.0, K_v=0.0, bottom_drag_r=0.0,
    momentum_advection="weno9", tracer_advection="weno7",
    barotropic_solver="explicit_substep", coriolis_scheme="explicit_ab2",
    barotropic_slow_forcing_ab2=True, barotropic_diffusion_alpha=0.0,
    n_barotropic_substeps=60)   # the outer AB2 integrator also steps the tracers
config = apply_silvestri_scheme(config, "W9V")
# W9V's divergence term uses full-divergence smoothness (Silvestri Eq. 45, CrossAndSelfUpwinding).
# Oceananigans' WENOVectorInvariant default pairs VelocityStencil vorticity with OnlySelfUpwinding
# divergence (Eq. 44), which legoESM selects with weno_divergence_smoothness = "standard".
config = config._replace(weno_divergence_smoothness="standard")

wall = np.ones((Ny, Nx))
state = rest_state_latlon_cgrid_ocean(grid, z, H_max=H, land_mask_override=wall,
                                      T_water_init_C=10.0, T_deep=10.0, S_uniform=30.0)

# ## Initial condition (NEMO `usrdef_istate.F90`, case 1)

U = 1.0
ℓ = 200e3
y = -Ny * Δ / 2 + (np.arange(Ny) + 0.5) * Δ          # cell-centre y, recovered from the index
in_jet = np.abs(y) <= ℓ + Δ / 4

u = np.zeros(state.u.data.shape)                       # (Ny, Nx + 1, 1); last column duplicates the first
u[in_jet, :, :] = U
S = np.where(in_jet[:, None, None], 35.0, 30.0) * np.ones(state.S.data.shape)
rng = np.random.default_rng(1234)
η = (-f0 * U * np.clip(y, -ℓ, ℓ) / g)[:, None] + 0.1 * rng.random((Ny, Nx)) - 0.05

state = state._replace(u=state.u.replace(data=jnp.asarray(u)),
                       S=state.S.replace(data=jnp.asarray(S)),
                       eta=state.eta.replace(data=jnp.asarray(η)))

# ## Simulation

model = LatLonCGridOceanModel(grid, z, config)
Δt = 600.0
state = model.seed_scan_carry(state, Δt)

steps_per_output = 36                                  # 6 hours
n_outputs = int(round(stop_days * 86400 / (Δt * steps_per_output)))


@jax.jit
def advance(s):
    return jax.lax.scan(lambda c, _: (model.step(c, Δt), None), s, None, length=steps_per_output)[0]


def vorticity(s):
    """ζ = ∂x v - ∂y u at cell corners (Ny + 1, Nx), zero on the free-slip walls."""
    uu = np.asarray(s.u.data)[:, :Nx, 0]
    vv = np.asarray(s.v.data)[:, :, 0]
    ζ = np.zeros((Ny + 1, Nx))
    ζ[1:Ny] = (vv[1:Ny] - np.roll(vv[1:Ny], 1, axis=1)) / Δ - (uu[1:] - uu[:-1]) / Δ
    return ζ


ds = Dataset(output, "w")
ds.createDimension("time", None)
ds.createDimension("y", Ny)
ds.createDimension("yf", Ny + 1)
ds.createDimension("x", Nx)
times = ds.createVariable("time", "f8", ("time",))
S_out = ds.createVariable("S", "f4", ("time", "y", "x"), zlib=True)
η_out = ds.createVariable("eta", "f4", ("time", "y", "x"), zlib=True)
ζ_out = ds.createVariable("zeta", "f4", ("time", "yf", "x"), zlib=True)
ds.createVariable("x", "f8", ("x",))[:] = -Nx * Δ / 2 + (np.arange(Nx) + 0.5) * Δ
ds.createVariable("y", "f8", ("y",))[:] = y
ds.createVariable("xf", "f8", ("x",))[:] = -Nx * Δ / 2 + np.arange(Nx) * Δ
ds.createVariable("yf", "f8", ("yf",))[:] = -Ny * Δ / 2 + np.arange(Ny + 1) * Δ


def save(n, s, t):
    times[n] = t
    S_out[n] = np.asarray(s.S.data)[:, :, 0]
    η_out[n] = np.asarray(s.eta.data)
    ζ_out[n] = vorticity(s)


save(0, state, 0.0)
wall_start = time.perf_counter()
for n in range(1, n_outputs + 1):
    tic = time.perf_counter()
    state = advance(state)
    jax.block_until_ready(state.u.data)
    t = n * steps_per_output * Δt
    save(n, state, t)
    if n % 20 == 0 or n == 1:
        uu = np.asarray(state.u.data); vv = np.asarray(state.v.data)
        print(f"t = {t / 86400:6.2f} days, max|u| = {np.abs(uu).max():.3f} m/s, max|v| = {np.abs(vv).max():.3f} m/s, "
              f"block wall time = {time.perf_counter() - tic:.2f} s", flush=True)
        if not np.isfinite(uu).all():
            print("NaN encountered; stopping", flush=True)
            break

ds.close()
print(f"Simulation wall time (including compilation): {time.perf_counter() - wall_start:.1f} s", flush=True)
