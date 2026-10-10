"""Download surface u, v, and potential temperature from GLORYS12 (GLOBAL_MULTIYEAR_PHY_001_030).

Reads the public Copernicus Marine ARCO Zarr store (no login needed) and writes
one NetCDF file with float32 surface fields over the North Atlantic domain.
"""

import sys
from pathlib import Path

import xarray as xr

from common import LAT_MAX, LAT_MIN, LON_MAX, LON_MIN, SPEED_END, SPEED_START

URL = ("https://s3.waw3-1.cloudferro.com/mdl-arco-time-025/arco/GLOBAL_MULTIYEAR_PHY_001_030/"
       "cmems_mod_glo_phy_my_0.083deg_P1D-m_202311/timeChunked.zarr")

out = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).parent / "data" / "glorys_surface.nc")
out.parent.mkdir(parents=True, exist_ok=True)

ds = xr.open_zarr(URL, zarr_format=2)
ds = ds[["uo", "vo", "thetao"]].sel(
    time=slice(SPEED_START, SPEED_END),
    longitude=slice(LON_MIN, LON_MAX),
    latitude=slice(LAT_MIN, LAT_MAX),
)
ds = ds.isel(elevation=int(abs(ds.elevation).argmin())).astype("float32")
ds.attrs["source"] = URL
ds.attrs["note"] = f"Surface level (z = {float(ds.elevation):.3f} m) subset for the North Atlantic"
print(ds)

encoding = {v: {"zlib": True, "complevel": 4} for v in ds.data_vars}
ds.to_netcdf(out, encoding=encoding)
print(f"wrote {out}")
