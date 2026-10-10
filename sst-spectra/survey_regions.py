"""Survey candidate regions for clear-sky usability in nighttime geostationary L3C SST.

For every 4th day from START to END, one nighttime hourly file per satellite is downloaded
(GOES-19 at 06 UTC, SEVIRI at 01 UTC) and each candidate box in regions.toml is scored:

  ocean_cells, clear_cells, clear_fraction  cells not flagged land; cells passing quality
                                            with finite SST; their ratio
  n_row_segments, n_col_segments            4°-long windows tiled from the box edge along
                                            each row (zonal) / column (meridional) that are
                                            entirely clear
  possible_row_segments, possible_col_...   same tiling, windows that are entirely ocean
  mean_zenith                               satellite zenith angle averaged over ocean cells
  sst_std                                   SST standard deviation over clear cells (K)

Each file is downloaded into its own temporary directory and deleted after processing.
Rows are appended to data/region_survey.csv as they complete, so the script is resumable:
rerunning skips (date, box) pairs already present. A per-box summary is then written to
data/region_survey_summary.csv.

    python survey_regions.py              # survey (resume) and summarize
    python survey_regions.py --summarize  # only recompute the summary from the CSV
"""

import csv
import subprocess
import sys
import tempfile
import threading
import time
import tomllib
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta
from pathlib import Path

import numpy as np
import pandas as pd
import requests
import xarray as xr

HERE = Path(__file__).parent
DATA = HERE / "data"
REGIONS = HERE / "regions.toml"
OUT = DATA / "region_survey.csv"
SUMMARY = DATA / "region_survey_summary.csv"

START, END, STEP_DAYS = date(2025, 9, 1), date(2026, 8, 31), 4
SEGMENT_DEG = 4.0
WORKERS = 6
CMR = "https://cmr.earthdata.nasa.gov/search/granules.umm_json"

SATELLITES = {
    # name: (collection short name, nighttime hour UTC, minimum quality_level)
    "goes": ("ABI_G19-STAR-L3C-v3.0", 6, 5),
    "seviri": ("SEVIRI_SST-OSISAF-L3C-v1.0", 1, 4),
}
LAND_BIT = 2

COLUMNS = ["date", "hour", "satellite", "box", "ocean_cells", "clear_cells", "clear_fraction",
           "n_row_segments", "n_col_segments", "possible_row_segments", "possible_col_segments",
           "mean_zenith", "sst_std", "nlat", "nlon", "segment_px"]

write_lock = threading.Lock()


def load_regions():
    with open(REGIONS, "rb") as f:
        regions = tomllib.load(f)
    return {k: v for k, v in regions.items() if isinstance(v, dict)}


def sample_dates():
    day = START
    while day <= END:
        yield day
        day += timedelta(STEP_DAYS)


def granule_urls(short_name):
    params = {"short_name": short_name, "provider": "POCLOUD", "page_size": 2000,
              "temporal": f"{START}T00:00:00Z,{END}T23:59:59Z", "sort_key": "start_date"}
    headers, urls = {}, []
    while True:
        for attempt in range(5):
            try:
                r = requests.get(CMR, params=params, headers=headers, timeout=120)
                r.raise_for_status()
                items = r.json()["items"]
                break
            except Exception as e:
                print(f"CMR query failed ({e}); retrying", flush=True)
                time.sleep(5 * (attempt + 1))
        else:
            raise RuntimeError("CMR query failed repeatedly")
        for item in items:
            urls += [l["URL"] for l in item["umm"]["RelatedUrls"]
                     if l["URL"].startswith("https://archive.podaac") and l["URL"].endswith(".nc")]
        if "CMR-Search-After" not in r.headers or not items:
            return sorted(set(urls))
        headers["CMR-Search-After"] = r.headers["CMR-Search-After"]


def download(url, directory):
    path = Path(directory) / url.rsplit("/", 1)[1]
    jar = Path(directory) / "cookies"
    subprocess.run(["curl", "-sSfL", "--retry", "4", "-n", "-c", jar, "-b", jar, "-o", path, url],
                   check=True, timeout=900)
    return path


def count_segments(mask, n):
    """Number of n-long windows, tiled from index 0 along rows and along columns, that are all True."""
    ny, nx = mask.shape
    kx, ky = nx // n, ny // n
    rows = mask[:, :kx * n].reshape(ny, kx, n).all(axis=2).sum() if kx else 0
    cols = mask[:ky * n, :].reshape(ky, n, nx).all(axis=1).sum() if ky else 0
    return int(rows), int(cols)


def score_box(ds, box, min_quality):
    lat0, lat1 = box["lat"]
    lon0, lon1 = box["lon"]
    lat, lon = ds.lat.values, ds.lon.values
    j = np.where((lat > lat0) & (lat < lat1))[0]
    i = np.where((lon > lon0) & (lon < lon1))[0]
    sub = ds.isel(time=0, lat=slice(j.min(), j.max() + 1), lon=slice(i.min(), i.max() + 1))
    res = float(abs(np.median(np.diff(sub.lat.values))))
    n = int(round(SEGMENT_DEG / res))

    sst = sub.sea_surface_temperature.values.astype("float64")
    q = sub.quality_level.values.astype("float64")  # NaN where fill
    flags = sub.l2p_flags.values.astype("int64")
    sza = sub.satellite_zenith_angle.values.astype("float64")

    ocean = (flags & LAND_BIT) == 0
    clear = ocean & np.isfinite(sst) & (q >= min_quality)
    n_rows, n_cols = count_segments(clear, n)
    p_rows, p_cols = count_segments(ocean, n)
    ocean_sza = sza[ocean & np.isfinite(sza)]
    clear_sst = sst[clear]
    return {
        "ocean_cells": int(ocean.sum()),
        "clear_cells": int(clear.sum()),
        "clear_fraction": clear.sum() / ocean.sum() if ocean.any() else np.nan,
        "n_row_segments": n_rows,
        "n_col_segments": n_cols,
        "possible_row_segments": p_rows,
        "possible_col_segments": p_cols,
        "mean_zenith": ocean_sza.mean() if ocean_sza.size else np.nan,
        "sst_std": clear_sst.std() if clear_sst.size > 1 else np.nan,
        "nlat": sub.sizes["lat"],
        "nlon": sub.sizes["lon"],
        "segment_px": n,
    }


def append_rows(rows):
    with write_lock:
        new = not OUT.exists()
        with open(OUT, "a", newline="") as f:
            w = csv.DictWriter(f, fieldnames=COLUMNS)
            if new:
                w.writeheader()
            w.writerows(rows)


def process_file(task):
    day, name, url, boxes = task
    short_name, hour, min_quality = SATELLITES[name]
    err = None
    for attempt in range(3):
        try:
            with tempfile.TemporaryDirectory(dir=DATA, prefix="tmp_") as tmp:
                path = download(url, tmp)
                with xr.open_dataset(path, engine="h5netcdf") as ds:
                    rows = []
                    for key, box in boxes.items():
                        r = score_box(ds, box, min_quality)
                        r.update(date=day.isoformat(), hour=hour, satellite=name, box=key)
                        rows.append(r)
            append_rows(rows)
            segs = sum(r["n_row_segments"] + r["n_col_segments"] for r in rows)
            print(f"{day} {name}: {len(rows)} boxes, {segs} clear segments", flush=True)
            return True
        except Exception as e:
            err = e
            time.sleep(10 * (attempt + 1))
    print(f"FAILED {day} {name} {url}: {err!r}", flush=True)
    return False


def survey():
    regions = load_regions()
    done = set()
    if OUT.exists():
        prev = pd.read_csv(OUT)
        done = set(zip(prev["date"], prev["box"]))
    DATA.mkdir(exist_ok=True)

    tasks, missing = [], []
    for name, (short_name, hour, _) in SATELLITES.items():
        boxes = {k: v for k, v in regions.items() if v["satellite"] == name}
        if not boxes:
            continue
        urls = granule_urls(short_name)
        by_stamp = {u.rsplit("/", 1)[1][:10]: u for u in urls}
        print(f"{name}: {len(urls)} granules in window, {len(boxes)} boxes", flush=True)
        for day in sample_dates():
            todo = {k: v for k, v in boxes.items() if (day.isoformat(), k) not in done}
            if not todo:
                continue
            stamp = f"{day:%Y%m%d}{hour:02d}"
            if stamp not in by_stamp:
                missing.append((day, name))
                continue
            tasks.append((day, name, by_stamp[stamp], todo))
    for day, name in missing:
        print(f"missing granule {day} {name}", flush=True)
    print(f"{len(tasks)} files to process, {len(missing)} missing", flush=True)

    t0 = time.time()
    with ThreadPoolExecutor(WORKERS) as pool:
        ok = list(pool.map(process_file, tasks))
    print(f"processed {sum(ok)}/{len(tasks)} files in {time.time() - t0:.0f} s", flush=True)


def season(month):
    return {12: "DJF", 1: "DJF", 2: "DJF", 3: "MAM", 4: "MAM", 5: "MAM",
            6: "JJA", 7: "JJA", 8: "JJA", 9: "SON", 10: "SON", 11: "SON"}[month]


def summarize():
    regions = load_regions()
    df = pd.read_csv(OUT).drop_duplicates(["date", "box"]).sort_values(["box", "date"])
    df["segments"] = df["n_row_segments"] + df["n_col_segments"]
    df["possible"] = df["possible_row_segments"] + df["possible_col_segments"]
    df["season"] = pd.to_datetime(df["date"]).dt.month.map(season)

    rows = []
    for key, g in df.groupby("box"):
        r = {
            "box": key,
            "name": regions[key]["name"],
            "satellite": regions[key]["satellite"],
            "n_images": len(g),
            "ocean_fraction": g["ocean_cells"].sum() / (g["nlat"] * g["nlon"]).sum(),
            "mean_clear_fraction": g["clear_fraction"].mean(),
            "median_clear_fraction": g["clear_fraction"].median(),
            "mean_segments_per_image": g["segments"].mean(),
            "mean_row_segments": g["n_row_segments"].mean(),
            "mean_col_segments": g["n_col_segments"].mean(),
            "possible_segments_per_image": g["possible"].mean(),
            "clear_segment_fraction": g["segments"].sum() / g["possible"].sum(),
            "frac_images_ge10_segments": (g["segments"] >= 10).mean(),
            "mean_zenith": g["mean_zenith"].mean(),
            "mean_sst_std": g["sst_std"].mean(),
        }
        for s in ["DJF", "MAM", "JJA", "SON"]:
            gs = g[g["season"] == s]
            r[f"segments_{s}"] = gs["segments"].mean() if len(gs) else np.nan
            r[f"n_images_{s}"] = len(gs)
        rows.append(r)
    out = pd.DataFrame(rows).sort_values("mean_segments_per_image", ascending=False)
    out.to_csv(SUMMARY, index=False, float_format="%.4f")
    with pd.option_context("display.width", 250, "display.max_columns", 50):
        print(out.round(3).to_string(index=False))
    print(f"wrote {SUMMARY}", flush=True)


if __name__ == "__main__":
    if "--summarize" not in sys.argv:
        survey()
    summarize()
