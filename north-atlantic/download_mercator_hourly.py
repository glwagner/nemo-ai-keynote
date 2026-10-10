"""Download hourly-mean surface u, v, and potential temperature from the Mercator 1/12° operational
analysis (GLOBAL_ANALYSISFORECAST_PHY_001_024, dataset cmems_mod_glo_phy_anfc_0.083deg_PT1H-m).

This is the real-time NEMO system from the same model family as GLORYS12, archived from
June 2022. Reads the public Copernicus Marine ARCO Zarr store (no login needed).

    python download_mercator_hourly.py START END   # writes data/mercator_hourly_START_END.nc
"""

import sys
from pathlib import Path

import xarray as xr

from common import LAT_MAX, LAT_MIN, LON_MAX, LON_MIN

URL = ("https://s3.waw3-1.cloudferro.com/mdl-arco-time-014/arco/GLOBAL_ANALYSISFORECAST_PHY_001_024/"
       "cmems_mod_glo_phy_anfc_0.083deg_PT1H-m_202406/timeChunked.zarr")

start, end = sys.argv[1:3]
out = Path(__file__).parent / "data" / f"mercator_hourly_{start}_{end}.nc"

ds = xr.open_zarr(URL, zarr_format=2)
ds = ds[["uo", "vo", "thetao"]].sel(
    time=slice(f"{start}T00:00", f"{end}T23:59"),
    longitude=slice(LON_MIN, LON_MAX),
    latitude=slice(LAT_MIN, LAT_MAX),
)
if "elevation" in ds.dims:
    ds = ds.isel(elevation=int(abs(ds.elevation).argmin()))
elif "depth" in ds.dims:
    ds = ds.isel(depth=0)
ds = ds.astype("float32")
ds.attrs["source"] = URL
ds.attrs["note"] = "Surface-level hourly means subset for the North Atlantic"
print(ds, flush=True)

ds.to_netcdf(out, encoding={v: {"zlib": True, "complevel": 4} for v in ds.data_vars})
print(f"wrote {out}")
