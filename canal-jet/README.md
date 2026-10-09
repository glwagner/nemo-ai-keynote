# Barotropic jet instability: NEMO vs Oceananigans vs legoESM

NEMO 4.2.2's `CANAL` test case (`nn_initcase = 1`, a geostrophic zonal jet), replicated in
[Oceananigans](https://github.com/CliMA/Oceananigans.jl) and in the ocean component of
[legoESM](https://github.com/climate-federation/legoESM) on the same grid with the same initial condition,
but different numerics.

| | |
|---|---|
| Domain | Channel periodic in x (2005 km), walls in y (995 km), flat bottom 1000 m deep |
| Grid | 5 km, 401 × 199 ocean cells, one vertical level |
| Rotation | f-plane at 38.5ᵒN |
| Initial condition | 1 m s⁻¹ top-hat jet over \|y\| ≤ 200 km in geostrophic balance; uniform random noise in [-5, 5] cm added to the free surface |
| Tracer | Salinity 35 inside the jet, 30 outside; passive dye (linear EOS with zero haline contraction) |
| Run | 60 days at Δt = 10 min, snapshots every 6 hours |

| | NEMO 4.2.2 | Oceananigans 0.113.5 | legoESM 1.0 (`b5204364b`) |
|---|---|---|---|
| Momentum advection | 3rd-order upstream-biased (UBS), flux form | `WENOVectorInvariant(order = 9)` (velocity-stencil vorticity, self-upwinded divergence) | WENO9 vector-invariant (`W9V` preset with `weno_divergence_smoothness = "standard"`, matching Oceananigans) |
| Tracer advection | UBS | `WENO(order = 9)` | WENO7 (no WENO9 tracer scheme exists) |
| Explicit dissipation | Bilaplacian viscosity, `rn_Uv = 1 m/s` grid-scale coefficient (≈1×10¹⁰ m⁴ s⁻¹) | None | None (defaults `A_h = 10⁴ m² s⁻¹` and SSH diffusion turned off) |
| Time stepping | Leapfrog, Asselin filter 0.1 | Quasi-Adams-Bashforth 2 | AB2 |
| Free surface | Nonlinear (z*), split-explicit | Linear, split-explicit, 60 substeps | Linear, split-explicit, 60 substeps, power-law filter |
| Grid | Cartesian f-plane (`CANAL` user grid) | `RectilinearGrid` + `FPlane` | Cartesian β-plane C-grid with β = 0 |
| Precision, hardware | Float64, CPU (MPI) | Float64, CPU (threads) | Float64, CPU (JAX/XLA) |

![NEMO vs Oceananigans vs legoESM](canal_jet_three_models.mp4)

## What differs

All three runs start from similar perturbation levels, then grow at very different rates.
The table gives zonal-anomaly variance of the dye:

| Day | NEMO | Oceananigans | legoESM |
|---|---|---|---|
| 2 | 2.2×10⁻⁸ | 3.9×10⁻⁹ | 2.0×10⁻⁸ |
| 6 | 2.1×10⁻⁶ | 3.1×10⁻⁸ | 4.4×10⁻⁴ |
| 10 | 1.1×10⁻⁴ | 1.0×10⁻⁷ | 0.25 |
| 16 | 2.1×10⁻² | 2.0×10⁻⁴ | 0.89 |
| 20 | 0.22 | 0.19 | 1.05 |
| 60 | 3.2 | 2.3 | 2.6 |

For comparison, linear theory for an inviscid vortex sheet at NEMO's ~250 km billow wavelength gives σ = kU/2 ≈ 1.3×10⁻⁵ s⁻¹.
That is ≈9× per day in dye variance.

- **legoESM** grows at ≈12× per day from day 2 and saturates by day ~10. That is the closest to sheet theory.
- **NEMO** grows steadily at ≈3× per day. Its bilaplacian viscosity and UBS smear the shear layers to ~50 km, which slows growth.
  It forms ~8 regularly spaced billows, then a few large, weak eddies (|ζ/f| ≲ 0.4).
- **Oceananigans** grows at only ≈1.5× per day for ~12 days, then rapidly.
- Oceananigans and legoESM share the same nominal momentum scheme (WENO9 vector-invariant). Both keep the shear layers sharp,
  then form compact, intense vortices (|ζ/f| ≈ 1) that merge. The late-stage fields look alike.
  The early growth rates differ by ~8× per day, so the two discretizations of nominally the same scheme
  differ in how they treat a one-cell shear layer. Why is not yet diagnosed.
  The cause is not the divergence smoothness. The `W9V` preset's default full-divergence smoothness
  and Oceananigans' self-upwinded divergence give legoESM dye variances within 2% through day 20.

## Performance

60 days (8640 steps) on an Apple-silicon Mac Studio, CPU only:

| | Wall time | Per step | Resources |
|---|---|---|---|
| Oceananigans | 125 s (109 s time-stepping + ~15 s Julia load/compile) | 13 ms | 8 threads |
| NEMO | 154 s | 18 ms | 8 MPI ranks |
| NEMO | ~126 s | 15 ms | 16 MPI ranks |
| legoESM | 635 s (2 s JIT compile) | 73 ms | JAX/XLA CPU, ≈4.5 cores busy on average (user + sys time / wall) |

legoESM is ~5× slower than Oceananigans and ~4× slower than NEMO here. It targets GPUs and TPUs.
On Apple silicon, its docs recommend the CPU backend because Metal is float32-only. Each run is a single measurement.

## legoESM notes

- The ocean component has a Cartesian β-plane C-grid (`create_beta_plane_cgrid_geometry`). With β = 0 it gives an exact f-plane,
  and an Oceananigans-mirroring config factory (`oceananigans_canonical_ocean_config`) exists for twin experiments.
  So the replica needed no source changes to the ocean model.
- Several defaults change the physics silently if not overridden: lateral viscosity `A_h = 10⁴ m² s⁻¹`,
  SSH diffusion `barotropic_diffusion_alpha = 0.01`, haline contraction `β_S = 7.4×10⁻⁴`, rest-state depth 5500 m, and an fp32 precision policy.
- `legoesm.core.transcendentals` loads glibc's `libm.so.6` at import time. Importing the ocean model therefore fails on macOS.
  `legoesm/macos-libm.patch` falls back to the platform libm.
- In the repository at `b5204364b`, ~78% of the 16,696 commits since February 2026 carry a Claude co-author trailer.
  It contains ~620k lines of package code and ~850k lines of tests; the lat-lon C-grid ocean model is one 15,900-line file.

## Flux-form momentum advection suppresses the instability

Momentum advection is vector-invariant here. With flux-form `momentum_advection = WENO(order = 9)`, the
Oceananigans jet stays nearly unperturbed for ~30 days. Diagnostic runs were seeded with a 250 km,
1 mm s⁻¹ meridional-velocity perturbation at the jet edges. The table gives the change in dye zonal-anomaly variance:

| Momentum advection | Top-hat jet | Jet with 10 km tanh edges |
|---|---|---|
| `WENO(order = 9)` (flux form) | oscillates and decays | grows ~4× per day |
| `Centered(order = 2)` (flux form) | oscillates and decays | grows ~4× per day |
| `WENOVectorInvariant(order = 9)` | grows 2.5–8× per day, saturates by day 10 | — |
| `VectorInvariant()` | grows 2–4× per day | — |

Suppression did not change with the time stepper (QAB2 or split RK3), the time step (10 or 2 min),
or the free-surface solver (split-explicit or implicit). Instantaneous flux-form and vector-invariant tendencies
agree closely on the same state (correlation 0.97–0.997), and the vertical-flux term is ~1% of the total.
So the cause is not a single wrong term; it remains unidentified. Flux-form momentum advection
fails only when the jet edge is a one-cell discontinuity.

Neither model is converged at 5 km for a discontinuous initial jet.

The unmodified NEMO `CANAL` namelist uses no explicit viscosity and no Asselin filter (`rn_atfp = 0`).
At 5 km resolution, grid-scale noise then accumulates until |U| > 10 m s⁻¹ at day 47.
Here, `nemo/namelist_cfg` adds the Asselin filter and bilaplacian viscosity.

## Running

### Oceananigans

```sh
julia --project -e 'using Pkg; Pkg.instantiate()'
julia --project -t 8 canal_jet.jl   # writes canal_jet_oceananigans.jld2 (~270 MB)
```

### NEMO

Requires XIOS2 (`XIOS2` branch of https://gitlab.in2p3.fr/ipsl/projets/xios-projects/xios), MPI, and NetCDF-Fortran.
On macOS with Homebrew (`gcc`, `open-mpi`, `netcdf`, `netcdf-fortran`):

```sh
# XIOS must be compiled with g++ (libstdc++). With clang/libc++, XIOS fails to parse durations like "10d".
cp nemo/arch-MAC_BREW-xios.fcm  $XIOS/arch/arch-MAC_BREW.fcm
cp nemo/arch-MAC_BREW-xios.path $XIOS/arch/arch-MAC_BREW.path
echo 'export NETCDF_DIR=/opt/homebrew' > $XIOS/arch/arch-MAC_BREW.env
(cd $XIOS && ./make_xios --prod --arch MAC_BREW --netcdf_lib netcdf4_seq --job 16)

cp nemo/arch-MAC_BREW-nemo.fcm $NEMO/arch/arch-MAC_BREW.fcm   # set %XIOS_HOME to your XIOS checkout
(cd $NEMO && ./makenemo -a CANAL -m MAC_BREW -n MY_CANAL -j 16)

cp nemo/namelist_cfg nemo/file_def_nemo-oce.xml $NEMO/tests/MY_CANAL/EXP00/
(cd $NEMO/tests/MY_CANAL/EXP00 && mpirun -np 16 ./nemo)
```

### legoESM

```sh
git clone https://github.com/climate-federation/legoESM && cd legoESM
git checkout b5204364b && git apply $THIS_DIR/legoesm/macos-libm.patch   # macOS only
uv sync
JAX_PLATFORMS=cpu JAX_ENABLE_X64=1 .venv/bin/python $THIS_DIR/canal_jet_legoesm.py   # writes canal_jet_legoesm.nc
```

### Animation

```sh
julia --project animate_comparison.jl $NEMO/tests/MY_CANAL/EXP00   # writes canal_jet_three_models.mp4
```

The script stitches NEMO's per-rank XIOS files (sequential NetCDF writes one file per rank) and
reads the Oceananigans JLD2 and legoESM NetCDF output from the current directory.
