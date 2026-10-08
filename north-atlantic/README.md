# Quarter-degree North Atlantic simulation

A cheap first configuration of a regional North Atlantic ocean simulation, built with
[Oceananigans](https://github.com/CliMA/Oceananigans.jl) and
[NumericalEarth](https://github.com/NumericalEarth/NumericalEarth.jl).

| | |
|---|---|
| Domain | 100ᵒW–15ᵒE, 5ᵒN–70ᵒN |
| Horizontal grid | 1/4ᵒ latitude-longitude, 460 × 260 |
| Vertical grid | 4 layers, faces at 0, 100, 600, 2000, 5000 m depth |
| Bathymetry | ETOPO, regridded; only the largest connected basin is kept |
| Initial condition | GLORYS 1/12ᵒ daily reanalysis (T, S, u, v) on 1 January 1993 |
| Boundary restoring | T and S restored to ECCO4 monthly fields at a 5-day timescale in 3ᵒ sponges on all four edges, tapering linearly to zero inward |
| Surface forcing | JRA55-do repeat-year atmosphere and radiation, bulk formulae; ocean temperature limited to freezing (no sea ice model) |
| Vertical mixing | CATKE (NumericalEarth default) |
| Run | 1 January – 1 April 1993; 2 days at Δt = 2 min, then Δt = 10 min |
| Output | Surface fields every 12 hours |

![Surface speed](north_atlantic_surface_speed.mp4)

## Running

```sh
julia --project -e 'using Pkg; Pkg.instantiate()'
julia --project -t 16 north_atlantic_simulation.jl   # ~40 min on 16 Apple-silicon CPU threads, including data download
julia --project animate_surface_speed.jl             # writes north_atlantic_surface_speed.mp4
```

Data downloads need credentials in environment variables:

- GLORYS (Copernicus Marine): `COPERNICUSMARINE_SERVICE_USERNAME`, `COPERNICUSMARINE_SERVICE_PASSWORD`
- ECCO (NASA Earthdata): `ECCO_USERNAME`, `ECCO_WEBDAV_PASSWORD`

NumericalEarth is pinned to commit `d07eb240` in `Project.toml`; `Manifest.toml` pins everything else.

## Inpainting workaround

`north_atlantic_simulation.jl` overrides `NumericalEarth.DataWrangling.remaining_gaps`. At the
pinned commit, that function counts missing values with a Float32 sum, which saturates at
2²⁴ ≈ 1.7×10⁷. The GLORYS subset for this domain has ~2.7×10⁷ land and sub-bathymetry cells,
so inpainting stopped after one pass and filled the rest with zeros. Without the override,
the initial salinity contains zeros next to 35 psu water, and surface currents reach 20 m s⁻¹
within hours. Remove the override once NumericalEarth fixes this upstream.

## Limitations

This is a first, deliberately cheap configuration. Four layers cannot resolve the mixed layer
or thermocline, so surface velocities represent the upper 100 m. Velocities are not restored at the
boundaries, so boundary currents entering through the sponges are not prescribed. The repeat-year
JRA55 forcing is not specific to 1993. Results have not been validated against observations.
