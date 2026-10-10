"""Collect hourly-mean surface temperature from the Mercator 1/12° operational analysis
(GLOBAL_ANALYSISFORECAST_PHY_001_024, cmems_mod_glo_phy_anfc_0.083deg_PT1H-m) for spectral regions.

For every day in [START, END], take the hour matching the satellite night image used for
that region (NIGHT_HOUR in common.py, or the region's own `hour`), and write data/model_<region>.nc with
dims (time, latitude, longitude). Reads the public ARCO Zarr store; no login needed.

    python download_model.py START END REGION [REGION ...]
"""

import sys
from pathlib import Path

import numpy as np
import pandas as pd
import xarray as xr

from common import NIGHT_HOUR, load_regions

URL = ("https://s3.waw3-1.cloudferro.com/mdl-arco-time-014/arco/GLOBAL_ANALYSISFORECAST_PHY_001_024/"
       "cmems_mod_glo_phy_anfc_0.083deg_PT1H-m_202406/timeChunked.zarr")

data_dir = Path(__file__).parent / "data"


def main():
    start, end, *keys = sys.argv[1:]
    regions = load_regions()
    store = xr.open_zarr(URL, zarr_format=2)["thetao"]
    store = store.isel(elevation=int(abs(store.elevation).argmin()))

    for key in keys:
        r = regions[key]
        out = data_dir / f"model_{key}.nc"
        times = pd.date_range(start, end, freq="D") + pd.Timedelta(hours=r.get("hour", NIGHT_HOUR[r["satellite"]]))
        da = store.sel(latitude=slice(*r["lat"]), longitude=slice(*r["lon"])).sel(time=times)
        da = da.astype("float32").rename("sst").load()
        da.attrs = {"units": "degC", "long_name": "hourly-mean top-level potential temperature",
                    "source": URL, "region": r["name"]}
        da.to_dataset().to_netcdf(out, encoding={"sst": {"zlib": True, "complevel": 4}})
        print(f"wrote {out}: {dict(da.sizes)}, {int(np.isfinite(da[0]).sum())} ocean cells", flush=True)


if __name__ == "__main__":
    main()
