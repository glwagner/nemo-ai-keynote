# Model-only SST-gradient spectra by region (Mercator 1/12° analysis, one year of nights).
#
#   julia --project=sst-spectra sst-spectra/plot_model_spectra.jl

using CairoMakie
using DelimitedFiles
using TOML

const dir = @__DIR__
regions = TOML.parsefile(joinpath(dir, "regions.toml"))

function read_spectrum(path)
    A, header = readdlm(path, ',', header = true)
    return Dict(String(h) => A[:, i] for (i, h) in enumerate(vec(header)))
end

keys_present = sort([k for k in keys(regions) if isfile(joinpath(dir, "data", "spectra_$(k)_model_combined.csv"))])

set_theme!(theme_light(), fontsize = 18)
fig = Figure(size = (1100, 800))
ax = Axis(fig[1, 1]; xscale = log10, yscale = log10,
          xlabel = "wavenumber k (cycles km⁻¹)", ylabel = "P_∇T  ((K km⁻¹)² per cycle km⁻¹)",
          title = "Mercator 1/12° analysis: SST-gradient spectra, Sep 2025 – Aug 2026 nights, 4° segments")
colors = Makie.wong_colors()
palette = vcat(colors, [:black, :gray50])

for (c, key) in enumerate(keys_present)
    s = read_spectrum(joinpath(dir, "data", "spectra_$(key)_model_combined.csv"))
    ok = s["count"] .> 0
    k = s["k"][ok]
    band!(ax, k, s["P_gradT_lo"][ok], s["P_gradT_hi"][ok]; color = (palette[c], 0.2))
    lines!(ax, k, s["P_gradT"][ok]; color = palette[c], linewidth = 2.5, label = regions[key]["name"])
end

# Grid scales of the 1/12° model at 30°N: Nyquist (2Δx) and a typical effective resolution (~8Δx)
Δx = 6371 * cosd(30) * deg2rad(1 / 12)
vlines!(ax, [1 / (2Δx)]; color = :gray40, linestyle = :dash)
vlines!(ax, [1 / (8Δx)]; color = :gray40, linestyle = :dot)
text!(ax, 1 / (2Δx), 1e-4; text = " 2Δx", color = :gray30, align = (:left, :bottom))
text!(ax, 1 / (8Δx), 1e-4; text = " 8Δx", color = :gray30, align = (:left, :bottom))

axislegend(ax; position = :lb, framevisible = false, labelsize = 15)
save(joinpath(dir, "model-gradient-spectra.png"), fig)
