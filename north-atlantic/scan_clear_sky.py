"""Scan the geostationary SST record for clear-sky coverage over the North Atlantic domain.

For each day in the overlap of GOES-19 (from 2025-04-01) and GLORYS12 (to 2026-08-25),
three hourly L3C files per satellite are sampled. Only the quality_level chunks that
cover the domain are read, using HTTP range requests. The clear fraction counts cells
that pass the same quality threshold used for the mosaic. GOES-19 is scored west of
40°W and SEVIRI east of it. Writes data/clear_sky_scan_START_END.csv.
"""

import csv
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta
from pathlib import Path

import earthaccess
import h5py
import numpy as np
import requests

from common import LAT_MAX, LAT_MIN, LON_MAX, LON_MIN
from download_geostationary_sst import CMR, SATELLITES

# Default: GOES-19 start to GLORYS12 end. Override with  python scan_clear_sky.py START END
START, END = (date.fromisoformat(a) for a in sys.argv[1:3]) if len(sys.argv) > 2 else (date(2025, 4, 1), date(2026, 8, 25))
HOURS = (6, 14, 22)
SPLIT_LON = -40.0
REGION = {"goes": (LON_MIN, SPLIT_LON), "seviri": (SPLIT_LON, LON_MAX)}

out = Path(__file__).parent / "data" / f"clear_sky_scan_{START}_{END}.csv"


def all_granule_urls(short_name):
    params = {"short_name": short_name, "provider": "POCLOUD", "page_size": 2000,
              "temporal": f"{START}T00:00:00Z,{END}T23:59:59Z", "sort_key": "start_date"}
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


def clear_fraction(fs, url, name):
    lon0, lon1 = REGION[name]
    min_quality = SATELLITES[name][1]
    for attempt in range(3):
        try:
            with fs.open(url, block_size=4 * 2**20, cache_type="bytes") as f, h5py.File(f) as h:
                lat, lon = h["lat"][:], h["lon"][:]
                j = np.where((lat >= LAT_MIN) & (lat <= LAT_MAX))[0]
                i = np.where((lon >= lon0) & (lon <= lon1))[0]
                q = h["quality_level"][0, j.min():j.max() + 1, i.min():i.max() + 1]
            return float((q >= min_quality).mean())
        except Exception as e:
            err = e
    print(f"failed {url}: {err}", flush=True)
    return float("nan")


def main():
    earthaccess.login(strategy="netrc")
    fs = earthaccess.get_fsspec_https_session()

    tasks = []
    for name, (short_name, _) in SATELLITES.items():
        urls = all_granule_urls(short_name)
        print(f"{name}: {len(urls)} granules", flush=True)
        by_stamp = {u.rsplit("/", 1)[1][:10]: u for u in urls}  # YYYYMMDDHH
        day = START
        while day <= END:
            for hour in HOURS:
                stamp = f"{day:%Y%m%d}{hour:02d}"
                if stamp in by_stamp:
                    tasks.append((day, hour, name, by_stamp[stamp]))
            day += timedelta(1)

    with ThreadPoolExecutor(32) as pool:
        fractions = list(pool.map(lambda t: clear_fraction(fs, t[3], t[2]), tasks))

    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["date", "hour", "satellite", "clear_fraction"])
        for (day, hour, name, _), frac in zip(tasks, fractions):
            w.writerow([day.isoformat(), hour, name, f"{frac:.4f}"])
    print(f"wrote {out} ({len(tasks)} samples)")


if __name__ == "__main__":
    main()
