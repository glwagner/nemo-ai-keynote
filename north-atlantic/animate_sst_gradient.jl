# Compare the magnitude of the horizontal SST gradient |∇T| in GLORYS12 (top)
# with a GOES-19 + Meteosat SEVIRI geostationary mosaic (bottom).
#
# Both fields are daily means on the GLORYS 1/12° grid; see download_geostationary_sst.py.
#
#   julia --project=north-atlantic north-atlantic/animate_sst_gradient.jl

using CairoMakie
using NCDatasets
using Dates
using Printf

const dir = @__DIR__
const R = 6371.0 # km

"""
    gradient_magnitude(T, λ, φ)

|∇T| in K km⁻¹ from centered differences on a regular longitude-latitude grid.
Cells with any missing neighbor (land, cloud, domain edge) are NaN.
"""
function gradient_magnitude(T, λ, φ)
    Δλ = deg2rad(λ[2] - λ[1])
    Δφ = deg2rad(φ[2] - φ[1])
    G = fill(NaN, size(T))
    for j in 2:size(T, 2)-1, i in 2:size(T, 1)-1
        ∂x = (T[i+1, j] - T[i-1, j]) / (2R * cosd(φ[j]) * Δλ)
        ∂y = (T[i, j+1] - T[i, j-1]) / (2R * Δφ)
        G[i, j] = sqrt(∂x^2 + ∂y^2)
    end
    return G
end

glorys = NCDataset(joinpath(dir, "data", "glorys_surface.nc"))
obs = NCDataset(joinpath(dir, "data", "geostationary_sst_daily.nc"))

λ = Float64.(obs["longitude"][:])
φ = Float64.(obs["latitude"][:])
@assert maximum(abs, λ .- glorys["longitude"][:]) < 1e-3
@assert maximum(abs, φ .- glorys["latitude"][:]) < 1e-3

dates = obs["time"][:]
glorys_index = [findfirst(==(d), glorys["time"][:]) for d in dates]

nanify(A) = Float64.(replace(A, missing => NaN))
model_sst(n) = nanify(glorys["thetao"][:, :, glorys_index[n]])
obs_sst(n) = nanify(obs["sst"][:, :, n])

# Land: missing in GLORYS. Ocean cells missing from the observations are cloud or no coverage.
land = isnan.(model_sst(1))
land_overlay = [l ? 1.0 : NaN for l in land]

aspect = (λ[end] - λ[1]) * cosd((φ[1] + φ[end]) / 2) / (φ[end] - φ[1])

background = RGBf(0.06, 0.07, 0.09)
land_color = RGBf(0.30, 0.31, 0.34)
cloud_color = RGBf(0.13, 0.14, 0.17)

set_theme!(theme_dark(), fontsize = 22, backgroundcolor = background)

fig = Figure(size = (1200, 1500))

n = Observable(1)
fields = [@lift(gradient_magnitude(model_sst($n), λ, φ)),
          @lift(gradient_magnitude(obs_sst($n), λ, φ))]
labels = ["GLORYS12 reanalysis (1/12°)",
          "Geostationary satellites: GOES-19 ABI + Meteosat SEVIRI, clear-sky daily mean"]

colorrange = (0, 0.15)
heatmaps = []
for (row, (G, label)) in enumerate(zip(fields, labels))
    ax = Axis(fig[row, 1]; aspect = AxisAspect(aspect), backgroundcolor = cloud_color,
              title = label, titlealign = :left, titlesize = 24, titlefont = :regular,
              xticks = -80:10:-10, yticks = 20:10:60,
              xtickformat = xs -> [@sprintf("%d°W", -x) for x in xs],
              ytickformat = ys -> [@sprintf("%d°N", y) for y in ys])
    hidespines!(ax)
    row == 1 && hidexdecorations!(ax; ticks = false)
    hm = heatmap!(ax, λ, φ, G; colormap = :thermal, colorrange, highclip = :white, nan_color = cloud_color)
    push!(heatmaps, hm)
    heatmap!(ax, λ, φ, land_overlay; colormap = [land_color, land_color], nan_color = :transparent)
end

Colorbar(fig[1:2, 2], first(heatmaps); label = "|∇T|  (K km⁻¹)", height = Relative(0.6))
title = @lift "Sea surface temperature gradient · " * Dates.format(dates[$n], "d U yyyy")
Label(fig[0, :], title; fontsize = 32, tellwidth = false)
rowgap!(fig.layout, 10)

record(fig, joinpath(dir, "sst-gradient-glorys-vs-geostationary.mp4"), eachindex(dates); framerate = 4) do i
    n[] = i
end

n[] = 15
save(joinpath(dir, "sst-gradient-glorys-vs-geostationary.png"), fig)

close(glorys)
close(obs)
