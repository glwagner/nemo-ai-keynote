"""Shared definitions for the SST-gradient spectra analysis."""

import tomllib
from pathlib import Path

# Night image hour (UTC) per satellite: ~01 local time at each sub-satellite longitude
NIGHT_HOUR = {"goes": 6, "seviri": 1}

PRODUCTS = {
    # satellite: (PO.DAAC collection, lowest quality_level stored, grid spacing in degrees)
    # ACSPO (GOES) quality is 0 or 5; OSI SAF (SEVIRI) quality runs 2-5 and the analysis
    # chooses its threshold from the stored quality_level.
    "goes": ("ABI_G19-STAR-L3C-v3.0", 5, 0.02),
    "seviri": ("SEVIRI_SST-OSISAF-L3C-v1.0", 3, 0.05),
}

LAND_FLAG = 2  # l2p_flags bit value for land in both products


def load_regions():
    with open(Path(__file__).parent / "regions.toml", "rb") as f:
        return tomllib.load(f)
