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
| Momentum advection | 3rd-order upstream-biased (UBS), flux form | `WENO(order = 9)` |
| Tracer advection | UBS | `WENO(order = 9)` |
| Explicit dissipation | Bilaplacian viscosity, `rn_Uv = 1 m/s` grid-scale coefficient (≈1×10¹⁰ m⁴ s⁻¹) | None (`closure = nothing`) |
| Time stepping | Leapfrog, Asselin filter 0.1 | Quasi-Adams-Bashforth 2 |
| Free surface | Split-explicit | Split-explicit, 60 substeps |
| Wall time | ≈2 min, 16 MPI ranks, Apple silicon | ≈1.6 min, 8 threads, same machine |

![NEMO vs Oceananigans](canal_jet_nemo_vs_oceananigans.mp4)

## What differs

- **Onset.** NEMO's shear layers grow from day 2 and roll up into billows by day 15–20.
  The Oceananigans jet stays nearly unperturbed for ~30 days, then grows faster than NEMO's ever did.
  Zonal-anomaly variance of the dye rises ~40× every 4 days in NEMO from day 2,
  and ~250× every 4 days in Oceananigans between days 30 and 42.
- **Shear-layer width and eddy size.** NEMO's vorticity sheets smear to ~50 km
  and roll up into a few large, weak eddies (|ζ/f| ≲ 0.4). Oceananigans keeps the
  sheets one or two cells thick, and they break into many small, intense vortices (|ζ/f| ≈ 1).

Free-surface noise in a 1000 m deep ocean projects almost entirely onto gravity waves, which radiate away.
The balanced (potential-vorticity) seed it leaves behind is tiny. So onset time is likely set
by how much each model's numerics perturb the sharp initial jet edges rather than by the imposed noise.
This explanation has not been tested, for example by varying noise amplitude, scheme, or resolution.
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
