# Animate surface speed from `north_atlantic_surface.jld2`, written by `north_atlantic_simulation.jl`.
# Run with `julia --project animate_surface_speed.jl`.

using Oceananigans
using CairoMakie
using Dates
using Printf

start_date = DateTime(1993, 1, 1)

st = FieldTimeSeries("north_atlantic_surface.jld2", "speed")
times = st.times
Nt = length(times)

λ, φ, _ = nodes(st)

# Land is masked with NaN.
land = interior(st[1], :, :, 1) .== 0

n = Observable(1)

speed = @lift begin
    s = Array(interior(st[$n], :, :, 1))
    s[land] .= NaN
    s
end

title = @lift begin
    date = start_date + Millisecond(round(Int, 1000 * times[$n]))
    "Surface speed, " * Dates.format(date, "d U yyyy")
end

fig = Figure(size = (1200, 760), fontsize = 16)

ax = Axis(fig[1, 1]; title, xlabel = "Longitude (ᵒ)", ylabel = "Latitude (ᵒ)",
          aspect = DataAspect(), backgroundcolor = :gray30)

hm = heatmap!(ax, λ, φ, speed; colormap = :speed, colorrange = (0, 1), nan_color = :gray30)
Colorbar(fig[1, 2], hm; label = "Speed (m s⁻¹)", height = Relative(0.8))

resize_to_layout!(fig)

record(fig, "north_atlantic_surface_speed.mp4", 1:Nt; framerate = 16) do nn
    n[] = nn
end

@info "Saved north_atlantic_surface_speed.mp4 with $Nt frames"
