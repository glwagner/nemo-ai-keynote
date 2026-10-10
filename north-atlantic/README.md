# North Atlantic surface dynamics: NEMO models and geostationary SST

Animations of North Atlantic surface currents and sea-surface temperature fronts, prepared October 2026.

| Output | Content |
|---|---|
| `glorys-surface-speed.mp4` / `.png` | GLORYS12 daily surface speed, 1 Jan – 25 Aug 2026 |
| `sst-gradient-glorys-vs-geostationary_2026-03-01_2026-03-31.mp4` / `.png` | Daily \|∇T\|, March 2026: GLORYS12 (top) vs GOES-19 + Meteosat mosaic (bottom) |
| `sst-gradient-mercator-vs-geostationary-hourly_2026-08-19_2026-08-28.mp4` / `.png` | Hourly \|∇T\| during the clearest 10 days on record: Mercator analysis (top) vs GOES-19 + Meteosat (bottom), 24 fps |
| `mercator-surface-speed-hourly_2026-08-19_2026-08-28.mp4` / `.png` | Hourly-mean surface speed from the Mercator analysis over the same 10 days |

Domain: 85°W–5°W, 20°N–60°N. The northern limit is set by SEVIRI L3C coverage. The domain and default windows are in `common.py`.

## Reproduce

```sh
python3 -m venv .venv && .venv/bin/pip install -r north-atlantic/requirements.txt
cd north-atlantic
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Daily: GLORYS12 vs daily satellite means
../.venv/bin/python download_glorys.py                        # ~0.7 GB, no login
../.venv/bin/python download_geostationary_sst.py             # March 2026; streams ~35 GB, needs Earthdata login in ~/.netrc
julia --project=. animate_surface_speed.jl
julia --project=. animate_sst_gradient.jl

# Clear-sky search
../.venv/bin/python scan_clear_sky.py                         # 2025-04-01 – 2026-08-25, ~3 h
../.venv/bin/python scan_clear_sky.py 2026-08-26 2026-10-08

# Hourly: Mercator analysis vs hourly satellite mosaics
../.venv/bin/python download_mercator_hourly.py 2026-08-19 2026-08-28
../.venv/bin/python download_geostationary_sst_hourly.py 2026-08-19 2026-08-28
julia --project=. animate_sst_gradient.jl 2026-08-19 2026-08-28 hourly
julia --project=. animate_surface_speed.jl 2026-08-19 2026-08-28
```

Downloaded data (`north-atlantic/data/`) and the rendered MP4s are not committed. The PNGs are mid-window stills.

## Data

- **GLORYS12** (`GLOBAL_MULTIYEAR_PHY_001_030`, dataset `cmems_mod_glo_phy_my_0.083deg_P1D-m`): Mercator Ocean / Copernicus Marine 1/12° NEMO-based reanalysis with daily means only, ending 25 Aug 2026. Surface level (0.49 m) `uo`, `vo`, `thetao` are read from the public ARCO Zarr store.
- **Mercator operational analysis** (`GLOBAL_ANALYSISFORECAST_PHY_001_024`, dataset `cmems_mod_glo_phy_anfc_0.083deg_PT1H-m`): the real-time 1/12° NEMO system from the same model family as GLORYS12. It provides hourly-mean surface fields from June 2022 to the present, on the same grid. Used for the hourly movies because GLORYS12 has no hourly output. It is an analysis, not the reanalysis.
- **GOES-19 ABI** (`ABI_G19-STAR-L3C-v3.0`): NOAA/STAR ACSPO hourly L3C subskin SST, 0.02°, available from 1 Apr 2025. GOES-East sits at 75.2°W. Only `quality_level == 5` is kept.
- **Meteosat SEVIRI** (`SEVIRI_SST-OSISAF-L3C-v1.0`): EUMETSAT OSI SAF hourly L3C subskin SST, 0.05°, from Meteosat-10 at 0°. Only `quality_level ≥ 4` is kept.

Both satellite products are distributed by NASA PO.DAAC.

## Choosing the clear-sky window

`scan_clear_sky.py` sampled three hourly files per satellite per day (06, 14, 22 UTC) from 1 Apr 2025 to 8 Oct 2026. It read only the domain's `quality_level` chunks and recorded the fraction of cells passing the quality threshold. GOES-19 was scored west of 40°W and SEVIRI east of it, and the two were combined with weights proportional to longitude span. Land cells count as not clear, so the scores rank days rather than give absolute ocean coverage.

The daily score has a median of 0.18. The clearest 10-day window is **19–28 Aug 2026** (mean 0.264). The best 7-, 14- and 31-day windows also fall in August–early September 2026. The cloudiest months are December–February. Each hourly frame in the chosen window still has satellite gradients for only about 40% of ocean cells.

## Method and caveats

- Hourly satellite pixels are bin-averaged onto the 1/12° model grid. In daily mode, the hourly bins are averaged over each UTC day. In hourly mode, each frame averages clear-sky bins within ±1 h. Native GOES resolution (0.02°) resolves finer fronts than are shown here.
- The two satellites are blended with weights exp(−θ/10°), where θ is the satellite zenith angle. Each region is dominated by the satellite with the most direct view. Inter-satellite biases are not removed, so a weak, broad blending zone near 35–45°W is possible.
- |∇T| uses centered differences on the sphere. A cell is blank unless all four neighbors are valid, so cloud edges do not create spurious fronts.
- Satellite values are clear-sky subskin temperatures. Model values are means of the top level (0.49 m) over 24 h (GLORYS) or 1 h (analysis). Diurnal warming and cloud sampling affect the two differently.
- Both GLORYS12 and the Mercator analysis assimilate satellite SST, so the bottom rows are not independent of the top rows.
- Late-summer fronts are weaker than late-winter ones, so the hourly movie uses a 0–0.1 K km⁻¹ color range and the March daily movie uses 0–0.15.
