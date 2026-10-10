"""Collect native-resolution nighttime geostationary SST for spectral regions.

For every day in [START, END], download the satellite's night image (NIGHT_HOUR in common.py)
once (or the region's own `hour` in regions.toml), extract each requested region at native resolution (GOES-19 0.02°, SEVIRI 0.05°),
set pixels below the stored quality threshold or on land to NaN, keep quality_level so the
analysis can tighten the threshold, and delete the image.
Daily extracts go to data/obs/<satellite>_<HH>/YYYYMMDD.nc and are combined into
data/obs_<region>.nc with dims (time, latitude, longitude), SST in °C stored as
int16 with 0.001 K precision.

    python download_obs.py START END REGION [REGION ...]
"""

import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd
import requests
import xarray as xr

from common import LAND_FLAG, NIGHT_HOUR, PRODUCTS, load_regions

CMR = "https://cmr.earthdata.nasa.gov/search/granules.umm_json"
WORKERS = 6

data_dir = Path(__file__).parent / "data"
ENCODING = {"dtype": "int16", "scale_factor": 0.001, "add_offset": 15.0, "_FillValue": -32768, "zlib": True}


def granule_urls(short_name, start, end):
    params = {"short_name": short_name, "provider": "POCLOUD", "page_size": 2000,
              "temporal": f"{start}T00:00:00Z,{end}T23:59:59Z", "sort_key": "start_date"}
    headers, urls = {}, []
    while True:
        r = requests.get(CMR, params=params, headers=headers, timeout=120)
        items = r.json()["items"]
        for item in items:
            urls += [l["URL"] for l in item["umm"]["RelatedUrls"]
                     if l["URL"].startswith("https://archive.podaac") and l["URL"].endswith(".nc")]
        if "CMR-Search-After" not in r.headers or not items:
            return sorted(set(urls))
        headers["CMR-Search-After"] = r.headers["CMR-Search-After"]


def download(url, directory):
    path = Path(directory) / url.rsplit("/", 1)[1]
    jar = Path(directory) / "cookies"
    subprocess.run(["curl", "-sSfL", "--retry", "4", "-n", "-c", jar, "-b", jar, "-o", path, url], check=True)
    return path


def extract(path, regions, min_quality):
    out = {}
    with xr.open_dataset(path, engine="h5netcdf") as ds:
        ds = ds.isel(time=0)
        for key, r in regions.items():
            sub = ds.sel(lat=slice(*r["lat"]) if ds.lat[0] < ds.lat[-1] else slice(*r["lat"][::-1]),
                         lon=slice(*r["lon"])).sortby("lat")
            sst = sub.sea_surface_temperature.values - 273.15
            ok = (sub.quality_level.values >= min_quality) & ((sub.l2p_flags.values & LAND_FLAG) == 0)
            dims = (f"lat_{key}", f"lon_{key}")
            coords = {f"lat_{key}": sub.lat.values, f"lon_{key}": sub.lon.values}
            out[f"sst_{key}"] = xr.DataArray(np.where(ok, sst, np.nan).astype("float32"), dims=dims, coords=coords)
            out[f"quality_{key}"] = xr.DataArray(np.where(ok, sub.quality_level.values, 0).astype("int8"),
                                                 dims=dims, coords=coords)
    return out


def process_day(day, url, satellite, hour, regions):
    out = data_dir / "obs" / f"{satellite}_{hour:02d}" / f"{day:%Y%m%d}.nc"
    if out.exists():
        return out
    for attempt in range(3):
        try:
            with tempfile.TemporaryDirectory(dir=data_dir) as tmp:
                fields = extract(download(url, tmp), regions, PRODUCTS[satellite][1])
            break
        except Exception as e:
            print(f"retry {day:%Y-%m-%d} {satellite}: {e}", flush=True)
    else:
        return None
    out.parent.mkdir(parents=True, exist_ok=True)
    ds = xr.Dataset(fields)
    ds.attrs["time"] = f"{day:%Y-%m-%d}T{hour:02d}:00"
    ds.to_netcdf(out, encoding={v: ENCODING if v.startswith("sst") else {"zlib": True} for v in ds.data_vars})
    clear = {k[4:]: f"{np.isfinite(v).mean():.0%}" for k, v in fields.items() if k.startswith("sst")}
    print(f"{day:%Y-%m-%d} {satellite} clear: {clear}", flush=True)
    return out


def main():
    start, end, *keys = sys.argv[1:]
    all_regions = load_regions()
    regions = {k: all_regions[k] for k in keys}

    image_hour = lambda r: r.get("hour", NIGHT_HOUR[r["satellite"]])
    for satellite, hour in sorted({(r["satellite"], image_hour(r)) for r in regions.values()}):
        sat_regions = {k: r for k, r in regions.items() if r["satellite"] == satellite and image_hour(r) == hour}
        urls = {datetime.strptime(u.rsplit("/", 1)[1][:10], "%Y%m%d%H"): u
                for u in granule_urls(PRODUCTS[satellite][0], start, end)}
        days = [d for d in pd.date_range(start, end, freq="D") if d + pd.Timedelta(hours=hour) in urls]
        print(f"{satellite}: {len(days)} night images for {list(sat_regions)}", flush=True)

        with ThreadPoolExecutor(WORKERS) as pool:
            paths = list(pool.map(lambda d: process_day(d, urls[d + pd.Timedelta(hours=hour)], satellite, hour, sat_regions),
                                  days))

        done = [(d, p) for d, p in zip(days, paths) if p is not None]
        for key in sat_regions:
            fields = []
            for d, p in done:
                with xr.open_dataset(p) as ds:
                    fields.append(ds[[f"sst_{key}", f"quality_{key}"]].load())
            ds = xr.concat(fields, dim="time").rename({f"lat_{key}": "latitude", f"lon_{key}": "longitude",
                                                       f"sst_{key}": "sst", f"quality_{key}": "quality_level"})
            ds = ds.assign_coords(time=[d + pd.Timedelta(hours=hour) for d, _ in done])
            ds["sst"].attrs = {"units": "degC", "note": "NaN = cloud, land, or quality below the stored threshold"}
            ds.attrs = {"source": PRODUCTS[satellite][0], "region": regions[key]["name"]}
            out = data_dir / f"obs_{key}.nc"
            ds.to_netcdf(out, encoding={"sst": ENCODING, "quality_level": {"zlib": True}})
            print(f"wrote {out}: {dict(ds.sizes)}", flush=True)


if __name__ == "__main__":
    main()
