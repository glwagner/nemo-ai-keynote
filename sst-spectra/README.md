# SST-gradient wavenumber spectra: 1/12° NEMO vs geostationary SST, by region

Analysis prepared October 2026. It asks at what scales a 1/12° NEMO ocean model loses sea-surface-temperature gradient variance compared with satellite observations, and how that depends on region.

- **Model**: Mercator 1/12° operational analysis (`GLOBAL_ANALYSISFORECAST_PHY_001_024`, hourly-mean top level). This is the real-time sibling of GLORYS12, used because it has hourly fields matching the satellite image times.
- **Observations**: NOAA ACSPO GOES-19 ABI L3C hourly SST at native 0.02°. EUMETSAT OSI SAF SEVIRI L3C was tested and rejected, as explained below.
- **Sampling**: one night image per day, 1 Sep 2025 – 31 Aug 2026.

## Findings

| Region | Model < ½ obs (obs on 1/12° grid) | Model < ½ obs (obs native) | Clear native segments |
|---|---:|---:|---:|
| Loop Current (Gulf of Mexico) | 23 km | 34 km | 32,523 |
| Gulf Stream | 24 km | 51 km | 5,307 |
| Brazil–Malvinas Confluence | 23 km | 28 km | 21,085 |
| Caribbean Sea | 22 km | 27 km | 8,236 |
| Sargasso Sea | 41 km | 41 km | 7,715 |
| Mid-Atlantic subtropical gyre (03 UTC) | 49 km | 66 km | 4,605 |

The "model < ½ obs" columns give the largest wavelength at which the model's |∇T| spectrum, on the satellite's clear segments, falls below half of the observed spectrum.

- **The model is deficient at small scales in every region, but the onset depends strongly on regime.** In energetic boundary-current regions the model holds up to ~50 km and halves at ~23 km on its own grid. In the quiet subtropical gyres the deficit starts near 100 km, halves at 40–65 km, and reaches 3–30× by 20 km. Small-scale SST variance in the gyres is mostly submesoscale, which 1/12° does not resolve. In boundary currents it is dominated by mesoscale fronts that the model represents. This interpretation is inferred, not tested here.
- **At 100–250 km the model has 1.2–1.7× more gradient variance than GOES-19**, even on identical clear segments. The cause is not established here.
- **The two comparisons answer different questions.** Comparing against observations averaged onto the model grid isolates model deficiency at scales the grid can represent. Comparing against native resolution adds what the grid cannot represent at all.

## Method

1. **Region choice** (`survey_regions.py`, `regions.toml`). Thirteen candidate 8°×8° boxes under the GOES-19 and Meteosat disks were scored on 92 nights for the yield of fully clear 4° segments. The Loop Current was best: 108 clear segments per night, 72% of nights usable, 33° zenith. Peru, Agulhas, North Brazil Current rings and the Gulf Stream extension were essentially unusable at night.
2. **Data** (`download_obs.py`, `download_model.py`). For each night, one hourly L3C image is downloaded (GOES 06 UTC, SEVIRI 01 UTC, ≈01 local time) and each region is extracted at native resolution. Model SST is taken for the same hour on its own grid.
3. **Spectra** (`spectra.jl`, validated by `test_spectra.jl` / `test_spectra.png`; driver `compute_spectra.jl`).
   - Rows and columns are tiled into non-overlapping 4° segments, and only fully valid segments are kept, so no gap filling is done.
   - Each segment is linearly detrended, Hann-windowed, and transformed to a one-sided PSD. P_∇T = (2πk)² P_T.
   - Spectra are averaged on common log-spaced bins. 95% intervals are block bootstraps over nights.
   - Four variants share the same bins:
     - model on all segments
     - model on the satellite-clear segments
     - satellite native
     - satellite block-averaged to 1/12°, using only cells whose pixels are all clear
4. **Plots** (`plot_model_spectra.jl`, `plot_spectra.jl`, `plot_masking.jl`, `plot_cross_satellite.jl`).

## Cloud masking and noise

- **GOES-19 ACSPO.** The analysis uses `quality_level == 5` and land-flagged pixels removed. Eroding a further 2 or 5 pixels from clouds and land leaves spectral shapes unchanged (`masking-sensitivity.png`), so cloud-edge contamination is not significant. In the Gulf Stream, erosion lowers the spectrum at all scales, which indicates selection away from cloudy fronts rather than contamination. The spectra show no white-noise plateau, so no noise correction is applied. Wavelengths shorter than 4 pixels (~8 km) are shaded.
- **SEVIRI OSI SAF L3C is rejected.** In the Levantine, Algerian, Benguela and Canary boxes its |∇T| spectra are flat from 200 to 20 km at nearly the same level in every region. They are insensitive to quality threshold (4 vs 5) and erosion. A same-ocean, same-hour test with both satellites viewing a mid-Atlantic box at 03 UTC (`cross-satellite-check.png`) shows SEVIRI 2× above GOES-19 at 200 km and more than 20× above it at 20 km, rising toward small scales. The excess is therefore retrieval or collation noise, not ocean variance. Two features of the product are consistent with this. OSI SAF hourly L3C takes single 15-minute pixels with nearest-neighbour remapping and no averaging, while ACSPO averages 10-minute images and 2-km pixels. SEVIRI also has a higher NEdT. Comparisons in the Mediterranean or eastern-boundary upwelling systems would need polar-orbiter L2P SST (e.g. VIIRS) instead.

## Caveats

- **Low-wavenumber bias.** 4° segments with a Hann window bias the lowest-wavenumber bins (wavelengths > ~40 km) by ±15–25% in absolute level (see `test_spectra.jl`). Model and observations are processed identically, so ratios are much less affected.
- **Clear-sky selection.** Clear nights and clear segments have weaker gradients than average, which shows in model-all vs model-clear. The model–observation comparison uses identical segments.
- **Not independent, and not GLORYS.** The Mercator analysis assimilates satellite SST, including at large scales, so the comparison is not independent there. It is the operational analysis, not the GLORYS12 reanalysis.
- **Sample sizes.** Gulf Stream, Caribbean, Sargasso and mid-Atlantic have only 600–1,000 clear segments on the model grid, which is reflected in their bootstrap bands.

## Reproduce

```sh
cd sst-spectra
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. test_spectra.jl
../.venv/bin/python survey_regions.py
REGIONS="loop_current gulf_stream brazil_malvinas sargasso caribbean levantine algerian benguela canary"
../.venv/bin/python download_obs.py 2025-09-01 2026-08-31 $REGIONS mid_atlantic_goes mid_atlantic_seviri   # ~23 GB streamed, Earthdata login
../.venv/bin/python download_model.py 2025-09-01 2026-08-31 $REGIONS mid_atlantic_goes mid_atlantic_seviri
julia --project=. compute_spectra.jl all                                    # plus --erode=2|5, --quality=5 variants
julia --project=. plot_spectra.jl
julia --project=. plot_masking.jl
julia --project=. plot_cross_satellite.jl
```

Data (`sst-spectra/data/`) are not committed.
