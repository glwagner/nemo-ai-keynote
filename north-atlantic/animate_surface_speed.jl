# Animate GLORYS12 daily surface speed over the North Atlantic.
#
#   julia --project=north-atlantic north-atlantic/animate_surface_speed.jl

using CairoMakie
using NCDatasets
using Dates
using Printf

const dir = @__DIR__

ds = NCDataset(joinpath(dir, "data", "glorys_surface.nc"))
λ = Float64.(ds["longitude"][:])
φ = Float64.(ds["latitude"][:])
t = ds["time"][:]
u = ds["uo"]
v = ds["vo"]

surface_speed(n) = replace(sqrt.(u[:, :, n] .^ 2 .+ v[:, :, n] .^ 2), missing => NaN)

# Aspect ratio for an equirectangular view centered on the domain's mid-latitude
aspect = (λ[end] - λ[1]) * cosd((φ[1] + φ[end]) / 2) / (φ[end] - φ[1])

background = RGBf(0.06, 0.07, 0.09)
land = RGBf(0.22, 0.23, 0.26)

set_theme!(theme_dark(), fontsize = 22, backgroundcolor = background)

fig = Figure(size = (1920, 1080))
ax = Axis(fig[1, 1]; aspect = AxisAspect(aspect), backgroundcolor = land,
          xticks = -80:10:-10, yticks = 20:10:60,
          xtickformat = xs -> [@sprintf("%d°W", -x) for x in xs],
          ytickformat = ys -> [@sprintf("%d°N", y) for y in ys])
hidespines!(ax)

n = Observable(1)
s = @lift surface_speed($n)
hm = heatmap!(ax, λ, φ, s; colormap = :magma, colorrange = (0, 1.5), nan_color = land)
Colorbar(fig[1, 2], hm; label = "Surface speed (m s⁻¹)", height = Relative(0.7))

title = @lift "GLORYS12 surface speed · " * Dates.format(t[$n], "d U yyyy")
Label(fig[0, :], title; fontsize = 30, tellwidth = false)

record(fig, joinpath(dir, "glorys-surface-speed.mp4"), 1:length(t); framerate = 12) do i
    n[] = i
end

n[] = findfirst(==(DateTime(2026, 3, 15)), t)
save(joinpath(dir, "glorys-surface-speed.png"), fig)

close(ds)
