"""Shared domain and time-window definitions for the North Atlantic visualization."""

# Domain: western boundary current to the European shelf. SEVIRI L3C stops at 60°N.
LON_MIN, LON_MAX = -85.0, -5.0
LAT_MIN, LAT_MAX = 20.0, 60.0

# GLORYS surface-velocity animation window (GLORYS12 daily ends 2026-08-25).
SPEED_START, SPEED_END = "2026-01-01", "2026-08-25"

# Default window for the GLORYS vs. geostationary |∇T| comparison (override on the command line).
GRADIENT_START, GRADIENT_END = "2026-03-01", "2026-03-31"
