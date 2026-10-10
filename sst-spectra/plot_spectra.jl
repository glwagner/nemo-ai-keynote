# Region-by-region comparison of SST-gradient spectra: Mercator 1/12° analysis vs
# native-resolution geostationary SST (output of compute_spectra.jl).
#
#   julia --project=sst-spectra sst-spectra/plot_spectra.jl
#
# Writes gradient-spectra-by-region.png, gradient-spectra-ratio.png, and
# data/effective_resolution.csv.
#
# The L3C satellite spectra show no white-noise plateau (they keep rolling off to the
# pixel scale), so no noise correction is applied. Wavelengths shorter than 4 satellite
# pixels are shaded as below the satellite's resolution.

using CairoMakie
using DelimitedFiles
using Printf
using TOML

const dir = @__DIR__
# GOES-19 regions only: SEVIRI L3C spectra are dominated by retrieval/collation noise
# (see plot_cross_satellite.jl and plot_masking.jl), so SEVIRI regions are excluded here.
const ORDER = ["loop_current", "gulf_stream", "brazil_malvinas", "caribbean", "sargasso", "mid_atlantic_goes"]
const PIXELS_RESOLVED = 4 # shade wavelengths shorter than this many satellite pixels

regions = TOML.parsefile(joinpath(dir, "regions.toml"))
spectrum_path(key, variant, direction = "combined") = joinpath(dir, "data", "spectra_$(key)_$(variant)_$(direction).csv")

function read_spectrum(path)
    A, header = readdlm(path, ',', header = true)
    s = Dict(String(h) => Float64.(A[:, i]) for (i, h) in enumerate(vec(header)))
    bad = s["count"] .== 0
    for v in ("P_T", "P_T_lo", "P_T_hi", "P_gradT", "P_gradT_lo", "P_gradT_hi")
        s[v][bad] .= NaN
    end
    return s
end

wavelength(k) = 1 ./ k
read_variants(key) = Dict(v => read_spectrum(spectrum_path(key, v)) for v in ("model", "model_clear", "obs", "obs_coarse"))

"""Largest wavelength at which `numerator / denominator` first drops below 1/2 (scanning toward small scales)."""
function half_power_wavelength(k, numerator, denominator)
    ratio = numerator ./ denominator
    ok = findall(isfinite, ratio)
    i = findfirst(j -> ratio[j] < 0.5, ok)
    return isnothing(i) ? NaN : wavelength(k[ok[i]])
end

keys_present = [k for k in ORDER if isfile(spectrum_path(k, "obs"))]
isempty(keys_present) && error("no observational spectra yet; run compute_spectra.jl all")

colors = Dict("model" => :black, "model_clear" => RGBf(0.35, 0.35, 0.35),
              "obs" => RGBf(0.85, 0.37, 0.0), "obs_coarse" => RGBf(0.0, 0.45, 0.70))
labels = Dict("obs" => "satellite, native resolution", "obs_coarse" => "satellite on the 1/12° grid",
              "model_clear" => "model, satellite-clear segments", "model" => "model, all segments")
styles = Dict("model_clear" => :dash)
palette = vcat(Makie.wong_colors(), [:black, :gray55])
wavelength_ticks = [5, 10, 20, 50, 100, 200, 400]

set_theme!(theme_light(), fontsize = 16)

#####
##### Figure 1: one panel per region
#####

ncols = 3
nrows = cld(length(keys_present), ncols)
fig = Figure(size = (1500, 430 * nrows + 80))
summary_rows = []

for (p, key) in enumerate(keys_present)
    r = regions[key]
    row, col = fldmod1(p, ncols)
    s = read_variants(key)
    ax = Axis(fig[row, col]; xscale = log10, yscale = log10, xreversed = true, xticks = wavelength_ticks,
              xlabel = row == nrows ? "wavelength (km)" : "", ylabel = col == 1 ? "P_∇T  ((K/km)² per cycle/km)" : "",
              title = r["name"], titlealign = :left)

    Δx_obs = s["obs"]["mean_dx_km"][1]
    λmin = minimum(wavelength(s["obs"]["k"]))
    vspan!(ax, λmin * 0.9, PIXELS_RESOLVED * Δx_obs; color = (:gray, 0.12))

    for v in ("obs", "obs_coarse", "model_clear", "model")
        k, P = s[v]["k"], s[v]["P_gradT"]
        ok = isfinite.(P) .& (P .> 0)
        band!(ax, wavelength(k[ok]), s[v]["P_gradT_lo"][ok], s[v]["P_gradT_hi"][ok]; color = (colors[v], 0.18))
        lines!(ax, wavelength(k[ok]), P[ok]; color = colors[v], linewidth = 2.5, linestyle = get(styles, v, :solid),
               label = labels[v])
    end

    text!(ax, 0.03, 0.03; space = :relative, align = (:left, :bottom), fontsize = 13,
          text = @sprintf("%s · %d clear native segments · %d nights", uppercase(r["satellite"]),
                          s["obs"]["nsegments"][1], s["obs"]["ngroups"][1]))
    p == 1 && axislegend(ax; position = :rt, framevisible = false, labelsize = 12, patchsize = (25, 10))

    k = s["model"]["k"]
    push!(summary_rows, (key,
                         half_power_wavelength(k, s["model_clear"]["P_gradT"], s["obs_coarse"]["P_gradT"]),
                         half_power_wavelength(k, s["model_clear"]["P_gradT"], s["obs"]["P_gradT"]),
                         s["obs"]["nsegments"][1], s["obs_coarse"]["nsegments"][1]))
end
Label(fig[0, :], "SST-gradient wavenumber spectra: Mercator 1/12° analysis vs GOES-19 ABI SST\n" *
                 "nights Sep 2025 – Aug 2026 · 4° segments · bands: 95% block bootstrap over nights · shading: < 4 satellite pixels";
      fontsize = 19, font = :bold)
save(joinpath(dir, "gradient-spectra-by-region.png"), fig)

#####
##### Figure 2: model / observation ratios, all regions
#####

fig2 = Figure(size = (1500, 650))
references = (("obs_coarse", "model ÷ satellite on the 1/12° grid (same segments)"),
              ("obs", "model ÷ satellite at native resolution"))
for (c, (reference, title)) in enumerate(references)
    ax = Axis(fig2[1, c]; xscale = log10, yscale = log10, xreversed = true, title, titlealign = :left,
              xlabel = "wavelength (km)", ylabel = c == 1 ? "ratio of P_∇T" : "",
              xticks = wavelength_ticks, yticks = [0.03, 0.1, 0.3, 0.5, 1, 2, 3])
    hlines!(ax, [1]; color = :gray30)
    hlines!(ax, [0.5]; color = :gray30, linestyle = :dot)
    for (i, key) in enumerate(keys_present)
        s = read_variants(key)
        ratio = s["model_clear"]["P_gradT"] ./ s[reference]["P_gradT"]
        ok = isfinite.(ratio)
        lines!(ax, wavelength(s["model"]["k"][ok]), ratio[ok]; color = palette[i], linewidth = 2.5,
               label = regions[key]["name"])
    end
    c == 2 && axislegend(ax; position = :lb, framevisible = false, labelsize = 13)
end
save(joinpath(dir, "gradient-spectra-ratio.png"), fig2)

open(joinpath(dir, "data", "effective_resolution.csv"), "w") do io
    println(io, "region,half_power_wavelength_vs_obs_on_model_grid_km,half_power_wavelength_vs_obs_native_km,native_segments,model_grid_segments")
    for (key, L1, L2, n1, n2) in summary_rows
        @printf(io, "%s,%.1f,%.1f,%d,%d\n", key, L1, L2, n1, n2)
    end
end
