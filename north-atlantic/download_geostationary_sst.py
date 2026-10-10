"""Build daily geostationary SST mosaics over the North Atlantic from GOES-East and Meteosat.

Sources (PO.DAAC, requires Earthdata login in ~/.netrc):
  * ABI_G19-STAR-L3C-v3.0       NOAA ACSPO hourly L3C SST from GOES-19 ABI (0.02°), GOES-East at 75.2°W
  * SEVIRI_SST-OSISAF-L3C-v1.0  EUMETSAT OSI SAF hourly L3C SST from Meteosat SEVIRI (0.05°), at 0°

Each hourly file is downloaded, subset to the domain, screened for quality, and
bin-averaged onto the GLORYS12 1/12° grid. Hourly bins are averaged into daily
means per satellite. The two satellites are then blended with weights
exp(-θ / θ₀) of the satellite zenith angle θ, so each region is dominated by the
satellite that views it most directly and the transition between them is smooth.

Hourly files are deleted after processing; one NetCDF per day is written to
data/geostationary/ and combined into data/geostationary_sst_daily.nc.
"""

import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta
from pathlib import Path

import numpy as np
import requests
import xarray as xr

from common import GRADIENT_END, GRADIENT_START, LAT_MAX, LAT_MIN, LON_MAX, LON_MIN

CMR = "https://cmr.earthdata.nasa.gov/search/granules.umm_json"

SATELLITES = {
    # name: (collection short name, minimum quality_level)
    "goes": ("ABI_G19-STAR-L3C-v3.0", 5),  # ACSPO uses 0 (bad) or 5 (best)
    "seviri": ("SEVIRI_SST-OSISAF-L3C-v1.0", 4),
}

ZENITH_SCALE = 10.0  # degrees; blending e-folding scale for satellite zenith angle
WORKERS = 6

# Target grid: GLORYS12 cell centers, λ = -180 + i/12, φ = -80 + j/12
RES = 1 / 12
I0 = int(np.ceil((LON_MIN + 180) / RES - 1e-6))
I1 = int(np.floor((LON_MAX + 180) / RES + 1e-6))
J0 = int(np.ceil((LAT_MIN + 80) / RES - 1e-6))
J1 = int(np.floor((LAT_MAX + 80) / RES + 1e-6))
LON = -180 + RES * np.arange(I0, I1 + 1)
LAT = -80 + RES * np.arange(J0, J1 + 1)
NX, NY = LON.size, LAT.size

data_dir = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).parent / "data")
daily_dir = data_dir / "geostationary"
daily_dir.mkdir(parents=True, exist_ok=True)


def granule_urls(short_name, start, end):
    params = {
        "short_name": short_name,
        "provider": "POCLOUD",
        "temporal": f"{start}T00:00:00Z,{end}T23:59:59Z",
        "page_size": 2000,
        "sort_key": "start_date",
    }
    items = requests.get(CMR, params=params, timeout=60).json()["items"]
    urls = []
    for item in items:
        for link in item["umm"]["RelatedUrls"]:
            u = link["URL"]
            if u.startswith("https://archive.podaac") and u.endswith(".nc"):
                urls.append(u)
    return sorted(set(urls))


def download(url, directory):
    path = Path(directory) / url.rsplit("/", 1)[1]
    jar = Path(directory) / "cookies"
    subprocess.run(["curl", "-sSfL", "--retry", "4", "-n", "-c", jar, "-b", jar, "-o", path, url], check=True)
    return path


def bin_hour(path, min_quality):
    """Return (sum of SST, sum of zenith, count) on the target grid for one hourly file."""
    with xr.open_dataset(path, engine="h5netcdf", mask_and_scale=True) as ds:
        lat, lon = ds.lat.values, ds.lon.values
        jlat = np.where((lat >= LAT_MIN - RES) & (lat <= LAT_MAX + RES))[0]
        ilon = np.where((lon >= LON_MIN - RES) & (lon <= LON_MAX + RES))[0]
        sub = ds.isel(time=0, lat=slice(jlat.min(), jlat.max() + 1), lon=slice(ilon.min(), ilon.max() + 1))
        sst = sub.sea_surface_temperature.values - 273.15
        q = sub.quality_level.values
        sza = sub.satellite_zenith_angle.values
        lat, lon = sub.lat.values, sub.lon.values

    i = np.rint((lon + 180) / RES).astype(int) - I0
    j = np.rint((lat + 80) / RES).astype(int) - J0
    jj, ii = np.meshgrid(j, i, indexing="ij")
    ok = (q >= min_quality) & np.isfinite(sst) & np.isfinite(sza)
    ok &= (ii >= 0) & (ii < NX) & (jj >= 0) & (jj < NY)
    k = (jj[ok] * NX + ii[ok]).ravel()
    n = NX * NY
    return (np.bincount(k, sst[ok], n), np.bincount(k, sza[ok], n), np.bincount(k, None, n))


def process_day(day, urls_by_sat):
    out = daily_dir / f"{day:%Y%m%d}.nc"
    if out.exists():
        return out
    fields = {}
    for name, (_, min_quality) in SATELLITES.items():
        urls = [u for u in urls_by_sat[name] if f"/{day:%Y%m%d}" in u]
        total = np.zeros((3, NX * NY))
        with tempfile.TemporaryDirectory(dir=data_dir) as tmp, ThreadPoolExecutor(WORKERS) as pool:
            for path in pool.map(lambda u: download(u, tmp), urls):
                total += np.array(bin_hour(path, min_quality))
                path.unlink()
        s, z, c = total.reshape(3, NY, NX)
        with np.errstate(invalid="ignore", divide="ignore"):
            fields[f"sst_{name}"] = np.where(c > 0, s / c, np.nan)
            fields[f"zenith_{name}"] = np.where(c > 0, z / c, np.nan)
        fields[f"n_{name}"] = c.astype("int16")
        print(f"  {day} {name}: {len(urls)} files, {(c > 0).mean():.1%} of cells observed", flush=True)

    # Zenith-weighted blend of the two daily means
    w = {n: np.where(np.isfinite(fields[f"sst_{n}"]), np.exp(-fields[f"zenith_{n}"] / ZENITH_SCALE), 0.0)
         for n in SATELLITES}
    wsum = sum(w.values())
    with np.errstate(invalid="ignore"):
        blend = sum(w[n] * np.nan_to_num(fields[f"sst_{n}"]) for n in SATELLITES) / wsum
    fields["sst"] = np.where(wsum > 0, blend, np.nan)

    ds = xr.Dataset(
        {k: (("latitude", "longitude"), v.astype("float32") if v.dtype.kind == "f" else v) for k, v in fields.items()},
        coords={"latitude": LAT, "longitude": LON},
    ).expand_dims(time=[np.datetime64(day, "ns")])
    ds["sst"].attrs = {"units": "degC", "long_name": "zenith-weighted GOES-19 + SEVIRI daily mean subskin SST"}
    ds.to_netcdf(out)
    return out


def main():
    start, end = date.fromisoformat(GRADIENT_START), date.fromisoformat(GRADIENT_END)
    urls_by_sat = {n: granule_urls(sn, start, end) for n, (sn, _) in SATELLITES.items()}
    for n, u in urls_by_sat.items():
        print(f"{n}: {len(u)} granules", flush=True)

    days = [start + timedelta(d) for d in range((end - start).days + 1)]
    paths = [process_day(day, urls_by_sat) for day in days]

    combined = xr.open_mfdataset(paths, combine="by_coords").load()
    combined.attrs = {
        "sources": "; ".join(sn for sn, _ in SATELLITES.values()) + " (PO.DAAC)",
        "method": __doc__,
    }
    combined.to_netcdf(data_dir / "geostationary_sst_daily.nc")
    print(f"wrote {data_dir / 'geostationary_sst_daily.nc'}")


if __name__ == "__main__":
    main()
