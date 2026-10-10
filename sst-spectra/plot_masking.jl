# Sensitivity of native-resolution satellite SST-gradient spectra to the cloud mask:
# quality threshold and erosion of pixels near clouds/land (compute_spectra.jl --quality --erode).
#
#   julia --project=sst-spectra sst-spectra/plot_masking.jl

using CairoMakie
using DelimitedFiles
using TOML

const dir = @__DIR__
const ORDER = ["loop_current", "gulf_stream", "brazil_malvinas", "sargasso", "caribbean",
               "levantine", "algerian", "benguela", "canary"]
const TAGS = ["", "_e2", "_e5", "_q5", "_q5_e2", "_q5_e5"]
const LABELS = Dict("" => "default mask", "_e2" => "erode 2 px", "_e5" => "erode 5 px",
                    "_q5" => "quality 5", "_q5_e2" => "quality 5, erode 2 px", "_q5_e5" => "quality 5, erode 5 px")

regions = TOML.parsefile(joinpath(dir, "regions.toml"))
path(key, variant, tag) = joinpath(dir, "data", "spectra_$(key)_$(variant)_combined$(tag).csv")

function read_spectrum(p)
    A, header = readdlm(p, ',', header = true)
    s = Dict(String(h) => Float64.(A[:, i]) for (i, h) in enumerate(vec(header)))
    s["P_gradT"][s["count"] .== 0] .= NaN
    return s
end

keys_present = [k for k in ORDER if isfile(path(k, "obs", ""))]
set_theme!(theme_light(), fontsize = 15)
fig = Figure(size = (1500, 420 * cld(length(keys_present), 3) + 60))
colors = Makie.wong_colors()

for (p, key) in enumerate(keys_present)
    row, col = fldmod1(p, 3)
    ax = Axis(fig[row, col]; xscale = log10, yscale = log10, xreversed = true, title = regions[key]["name"],
              titlealign = :left, xticks = [5, 10, 20, 50, 100, 200], xlabel = "wavelength (km)",
              ylabel = col == 1 ? "P_∇T  ((K/km)² per cycle/km)" : "")
    for (i, tag) in enumerate(TAGS)
        isfile(path(key, "obs", tag)) || continue
        s = read_spectrum(path(key, "obs", tag))
        n = Int(s["nsegments"][1])
        lines!(ax, 1 ./ s["k"], s["P_gradT"]; color = colors[i], linewidth = 2.5, label = "$(LABELS[tag]) ($n)")
    end
    m = read_spectrum(path(key, "model_clear", ""))
    lines!(ax, 1 ./ m["k"], m["P_gradT"]; color = :black, linestyle = :dash, linewidth = 2, label = "model, clear segments")
    axislegend(ax; position = :lb, framevisible = false, labelsize = 11, patchsize = (20, 8))
end
Label(fig[0, :], "Satellite SST-gradient spectra under different cloud masks (segment counts in parentheses)";
      fontsize = 19, font = :bold)
save(joinpath(dir, "masking-sensitivity.png"), fig)
