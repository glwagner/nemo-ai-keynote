# Cross-satellite check: GOES-19 ABI (ACSPO) and Meteosat SEVIRI (OSI SAF) viewing the same
# mid-Atlantic box (25–33°N, 42–34°W) at the same hour (03 UTC) on the same nights, with the
# Mercator analysis for reference.
#
#   julia --project=sst-spectra sst-spectra/plot_cross_satellite.jl

using CairoMakie
using DelimitedFiles

const dir = @__DIR__
path(key, variant) = joinpath(dir, "data", "spectra_$(key)_$(variant)_combined.csv")

function read_spectrum(p)
    A, header = readdlm(p, ',', header = true)
    s = Dict(String(h) => Float64.(A[:, i]) for (i, h) in enumerate(vec(header)))
    for v in ("P_gradT", "P_gradT_lo", "P_gradT_hi")
        s[v][s["count"] .== 0] .= NaN
    end
    return s
end

curves = [("mid_atlantic_goes", "obs", "GOES-19 ABI (ACSPO), native 0.02°", RGBf(0.85, 0.37, 0.0)),
          ("mid_atlantic_seviri", "obs", "Meteosat SEVIRI (OSI SAF), native 0.05°", RGBf(0.0, 0.62, 0.45)),
          ("mid_atlantic_goes", "obs_coarse", "GOES-19 on the 1/12° grid", RGBf(0.95, 0.65, 0.35)),
          ("mid_atlantic_seviri", "obs_coarse", "SEVIRI on the 1/12° grid", RGBf(0.45, 0.80, 0.65)),
          ("mid_atlantic_goes", "model", "Mercator 1/12° analysis, all segments", :black)]

set_theme!(theme_light(), fontsize = 17)
fig = Figure(size = (1000, 700))
ax = Axis(fig[1, 1]; xscale = log10, yscale = log10, xreversed = true, xticks = [5, 10, 20, 50, 100, 200],
          xlabel = "wavelength (km)", ylabel = "P_∇T  ((K/km)² per cycle/km)", titlealign = :left,
          title = "Same ocean, same hour: mid-Atlantic 25–33°N, 42–34°W, 03 UTC, Sep 2025 – Aug 2026")
for (key, variant, label, color) in curves
    s = read_spectrum(path(key, variant))
    ok = isfinite.(s["P_gradT"])
    λ = 1 ./ s["k"][ok]
    band!(ax, λ, s["P_gradT_lo"][ok], s["P_gradT_hi"][ok]; color = (color, 0.2))
    lines!(ax, λ, s["P_gradT"][ok]; color, linewidth = 3, linestyle = variant == "obs_coarse" ? :dash : :solid,
           label = "$label ($(Int(s["nsegments"][1])) segments)")
end
axislegend(ax; position = :lb, framevisible = false, labelsize = 14)
save(joinpath(dir, "cross-satellite-check.png"), fig)
