# North Atlantic surface dynamics: GLORYS12 and geostationary SST

Animations of North Atlantic surface currents and sea-surface temperature fronts, prepared October 2026.

| Output | Content |
|---|---|
| `glorys-surface-speed.mp4` / `.png` | GLORYS12 daily surface speed, 1 Jan – 25 Aug 2026 |
| `sst-gradient-glorys-vs-geostationary.mp4` / `.png` | Daily \|∇T\|, March 2026: GLORYS12 (top) vs GOES-19 + Meteosat mosaic (bottom) |

Domain: 85°W–5°W, 20°N–60°N. The northern limit is set by SEVIRI L3C coverage. Domain and time windows are in `common.py`.

## Reproduce

```sh
python3 -m venv .venv && .venv/bin/pip install -r north-atlantic/requirements.txt
cd north-atlantic
../.venv/bin/python download_glorys.py              # ~1 GB, no login
../.venv/bin/python download_geostationary_sst.py   # streams ~35 GB, needs Earthdata login in ~/.netrc
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. animate_surface_speed.jl
julia --project=. animate_sst_gradient.jl
```

Downloaded data (`north-atlantic/data/`) and the rendered MP4s are not committed; the PNGs are 15 March 2026 stills.

## Data

- **GLORYS12** (`GLOBAL_MULTIYEAR_PHY_001_030`, dataset `cmems_mod_glo_phy_my_0.083deg_P1D-m`): Mercator Ocean / Copernicus Marine 1/12° NEMO-based reanalysis with daily means. Surface level (0.49 m) `uo`, `vo`, `thetao` are read from the public ARCO Zarr store.
- **GOES-19 ABI** (`ABI_G19-STAR-L3C-v3.0`): NOAA/STAR ACSPO hourly L3C subskin SST, 0.02°. GOES-East sits at 75.2°W. Only `quality_level == 5` is kept.
- **Meteosat SEVIRI** (`SEVIRI_SST-OSISAF-L3C-v1.0`): EUMETSAT OSI SAF hourly L3C subskin SST, 0.05°, from Meteosat-10 at 0°. Only `quality_level ≥ 4` is kept.

Both satellite products are distributed by NASA PO.DAAC.

## Method and caveats

- Hourly satellite pixels are bin-averaged onto the GLORYS 1/12° grid, then averaged over each UTC day. This makes both rows the same resolution and the same daily averaging. Native GOES resolution (0.02°) resolves finer fronts than are shown here.
- The two satellites are blended with weights exp(−θ/10°), where θ is the daily mean satellite zenith angle. Each region is dominated by the satellite with the most direct view. Inter-satellite biases are not removed, so a weak, broad blending zone near 35–45°W is possible.
- |∇T| uses centered differences on the sphere. A cell is blank unless all four neighbors are valid, so cloud edges do not create spurious fronts.
- A satellite daily mean is an average over the clear-sky hours only, and is a subskin temperature. GLORYS is a 24-hour mean of the top model level (0.49 m). Diurnal warming and cloud sampling therefore affect the observations differently from the model.
- GLORYS assimilates satellite SST, so the bottom row is not independent of the top row.
