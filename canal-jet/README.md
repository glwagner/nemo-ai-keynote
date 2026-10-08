# Barotropic jet instability: NEMO vs Oceananigans

NEMO 4.2.2's `CANAL` test case (`nn_initcase = 1`, a geostrophic zonal jet) and an
[Oceananigans](https://github.com/CliMA/Oceananigans.jl) replica on the same grid with the same
initial condition, but different numerics.

| | |
|---|---|
| Domain | Channel periodic in x (2005 km), walls in y (995 km), flat bottom 1000 m deep |
| Grid | 5 km, 401 × 199 ocean cells, one vertical level |
| Rotation | f-plane at 38.5ᵒN |
| Initial condition | 1 m s⁻¹ top-hat jet over \|y\| ≤ 200 km in geostrophic balance; uniform random noise in [-5, 5] cm added to the free surface |
| Tracer | Salinity 35 inside the jet, 30 outside; passive dye (linear EOS with zero haline contraction) |
| Run | 60 days at Δt = 10 min, snapshots every 6 hours |

| | NEMO 4.2.2 | Oceananigans 0.113.5 |
|---|---|---|
| Momentum advection | 3rd-order upstream-biased (UBS), flux form | `WENOVectorInvariant(order = 9)` |
| Tracer advection | UBS | `WENO(order = 9)` |
| Explicit dissipation | Bilaplacian viscosity, `rn_Uv = 1 m/s` grid-scale coefficient (≈1×10¹⁰ m⁴ s⁻¹) | None (`closure = nothing`) |
| Time stepping | Leapfrog, Asselin filter 0.1 | Quasi-Adams-Bashforth 2 |
| Free surface | Split-explicit | Split-explicit, 60 substeps |
| Wall time | ≈2 min, 16 MPI ranks, Apple silicon | ≈1.6 min, 8 threads, same machine |

![NEMO vs Oceananigans](canal_jet_nemo_vs_oceananigans.mp4)

## What differs

- **Onset.** Both jets go unstable on similar timescales. NEMO's shear layers grow steadily from day 2:
  the dye's zonal-anomaly variance rises ~40× every 4 days.
  Oceananigans' grows slowly until day ~10, then very quickly. Both saturate around days 20–26.
- **Shear-layer width and eddy size.** NEMO's vorticity sheets smear to ~50 km and roll up into
  ~8 regularly spaced billows, then a few large, weak eddies (|ζ/f| ≲ 0.4). Oceananigans keeps the
  sheets one or two cells thick. They break into many small, intense vortices (|ζ/f| ≈ 1),
  which merge into compact, intense eddies.

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

### Animation

```sh
julia --project animate_comparison.jl $NEMO/tests/MY_CANAL/EXP00   # writes canal_jet_nemo_vs_oceananigans.mp4
```

The script stitches NEMO's per-rank XIOS files (sequential NetCDF writes one file per rank) and
reads the Oceananigans JLD2 output from the current directory.
