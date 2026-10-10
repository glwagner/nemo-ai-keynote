"""Build hourly geostationary SST mosaics over the North Atlantic from GOES-19 and Meteosat SEVIRI.

Same sources, quality screening, 1/12° binning, and zenith-weighted blending as
download_geostationary_sst.py, but every hourly L3C file is kept as its own time
level instead of being averaged into a daily mean. Hourly files are deleted after
binning; one NetCDF per day is written to data/geostationary_hourly/ and combined
into data/geostationary_sst_hourly_START_END.nc.

    python download_geostationary_sst_hourly.py START END
"""

import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta

import numpy as np
import xarray as xr

from download_geostationary_sst import (LAT, LON, NX, NY, SATELLITES, WORKERS, bin_hour, blend, data_dir,
                                        download, granule_urls)

hourly_dir = data_dir / "geostationary_hourly"
hourly_dir.mkdir(parents=True, exist_ok=True)


def file_time(url):
    return datetime.strptime(url.rsplit("/", 1)[1][:14], "%Y%m%d%H%M%S")


def process_day(day, urls_by_sat):
    out = hourly_dir / f"{day:%Y%m%d}.nc"
    if out.exists():
        return out
    times = [datetime(day.year, day.month, day.day) + timedelta(hours=h) for h in range(24)]
    fields = {}
    for name, (_, min_quality) in SATELLITES.items():
        urls = {file_time(u): u for u in urls_by_sat[name] if file_time(u).date() == day}
        sst = np.full((24, NY, NX), np.nan)
        zenith = np.full((24, NY, NX), np.nan)

        def bin_one(item):
            t, url = item
            with tempfile.TemporaryDirectory(dir=data_dir) as tmp:
                return t, bin_hour(download(url, tmp), min_quality)

        with ThreadPoolExecutor(WORKERS) as pool:
            for t, (s, z, c) in pool.map(bin_one, urls.items()):
                h = times.index(t)
                s, z, c = s.reshape(NY, NX), z.reshape(NY, NX), c.reshape(NY, NX)
                with np.errstate(invalid="ignore", divide="ignore"):
                    sst[h] = np.where(c > 0, s / c, np.nan)
                    zenith[h] = np.where(c > 0, z / c, np.nan)
        fields[f"sst_{name}"], fields[f"zenith_{name}"] = sst, zenith
        observed = np.isfinite(sst).mean(axis=(1, 2))
        print(f"  {day} {name}: {len(urls)} files, {observed.mean():.1%} of cells observed per hour", flush=True)

    fields["sst"] = blend(fields)

    ds = xr.Dataset(
        {k: (("time", "latitude", "longitude"), v.astype("float32")) for k, v in fields.items()},
        coords={"time": np.array(times, dtype="datetime64[ns]"), "latitude": LAT, "longitude": LON},
    )
    ds["sst"].attrs = {"units": "degC", "long_name": "zenith-weighted GOES-19 + SEVIRI hourly subskin SST"}
    ds.to_netcdf(out, encoding={v: {"zlib": True, "complevel": 4} for v in ds.data_vars})
    return out


def main():
    start, end = map(date.fromisoformat, sys.argv[1:3])
    urls_by_sat = {n: granule_urls(sn, start, end) for n, (sn, _) in SATELLITES.items()}
    for n, u in urls_by_sat.items():
        print(f"{n}: {len(u)} granules", flush=True)

    days = [start + timedelta(d) for d in range((end - start).days + 1)]
    paths = [process_day(day, urls_by_sat) for day in days]

    combined = xr.open_mfdataset(paths, combine="by_coords")[["sst"]].load()
    combined.attrs = {
        "sources": "; ".join(sn for sn, _ in SATELLITES.values()) + " (PO.DAAC)",
        "method": __doc__,
    }
    out = data_dir / f"geostationary_sst_hourly_{start}_{end}.nc"
    combined.to_netcdf(out, encoding={"sst": {"zlib": True, "complevel": 4}})
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
