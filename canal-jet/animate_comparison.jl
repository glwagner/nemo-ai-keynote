# Side-by-side animation of the NEMO CANAL jet and its Oceananigans and legoESM replicas.
#
# Run with `julia --project animate_comparison.jl /path/to/NEMO/EXP00 [output.mp4]`, where EXP00 holds
# NEMO's per-rank XIOS output `CANAL_grid_T_*.nc` (soce, ssrelvor) and `canal_jet_oceananigans.jld2`
# (written by `canal_jet.jl`) and `canal_jet_legoesm.nc` (written by `canal_jet_legoesm.py`) are in the
# current directory.

using Oceananigans
using JLD2
using NCDatasets
using CairoMakie
using Printf

nemo_dir = ARGS[1]
output = length(ARGS) > 1 ? ARGS[2] : "canal_jet_three_models.mp4"

# ## NEMO: stitch per-rank XIOS files into global (x, y, t) arrays

"Assemble the global field `name` on grid `loc` (\"T\" or \"F\") from NEMO's per-rank files."
function stitch_nemo(files, name, loc)
    pieces = map(files) do file
        NCDataset(file) do ds
            i₀ = ds.attrib["ibegin_grid_$loc"]
            j₀ = ds.attrib["jbegin_grid_$loc"]
            data = Array(ds[name])
            data = ndims(data) == 4 ? data[:, :, 1, :] : data # surface level of (x, y, z, t)
            (i₀, j₀, data)
        end
    end

    Nx = maximum(i₀ + size(d, 1) for (i₀, j₀, d) in pieces)
    Ny = maximum(j₀ + size(d, 2) for (i₀, j₀, d) in pieces)
    Nt = size(pieces[1][3], 3)
    global_field = fill(NaN, Nx, Ny, Nt)

    for (i₀, j₀, d) in pieces
        global_field[i₀+1:i₀+size(d, 1), j₀+1:j₀+size(d, 2), :] .= coalesce.(d, NaN)
    end

    return global_field
end

files = sort(filter(f -> occursin(r"^CANAL_grid_T_\d+\.nc$", f), readdir(nemo_dir)))
files = joinpath.(nemo_dir, files)

# T rows 1 and 201 are land; F rows 1 and 200 lie on the walls, matching Oceananigans' y-faces.
S_nemo = stitch_nemo(files, "soce", "T")[:, 2:end-1, :]
ζ_nemo = stitch_nemo(files, "ssrelvor", "F")[:, 1:200, :]

Δ = 5 # km
xᶜ = range(-1000, 1000, step = Δ)
yᶜ = range(-495, 495, step = Δ)
xᶠ = xᶜ .+ Δ / 2
yᶠ = range(-497.5, 497.5, step = Δ)

# NEMO writes its first snapshot 6 hours in; Oceananigans also saves the initial state.
Nt_nemo = size(S_nemo, 3)

# ## Oceananigans

S_ocnn = FieldTimeSeries("canal_jet_oceananigans.jld2", "S")
ζ_ocnn = FieldTimeSeries("canal_jet_oceananigans.jld2", "ζ")
times = S_ocnn.times

xᶜ_ocnn, yᶜ_ocnn, _ = nodes(S_ocnn)
xᶠ_ocnn, yᶠ_ocnn, _ = nodes(ζ_ocnn)

# ## legoESM (written by `canal_jet_legoesm.py`, also saving the initial state)

lego = NCDataset("canal_jet_legoesm.nc")
S_lego = lego["S"]       # (x, y, time) in Julia's column-major order
ζ_lego = lego["zeta"]
xᶜ_lego, yᶜ_lego = lego["x"][:] .* 1e-3, lego["y"][:] .* 1e-3
xᶠ_lego, yᶠ_lego = lego["xf"][:] .* 1e-3, lego["yf"][:] .* 1e-3

Nt = minimum((Nt_nemo, length(times) - 1, length(lego["time"]) - 1))

# ## Figure

f₀ = 2 * 7.292115e-5 * sind(38.5)
km = 1e-3

n = Observable(1)

S₁ = @lift S_nemo[:, :, $n]
ζ₁ = @lift ζ_nemo[:, :, $n] ./ f₀
S₂ = @lift interior(S_ocnn[$n + 1], :, :, 1)
ζ₂ = @lift interior(ζ_ocnn[$n + 1], :, :, 1) ./ f₀
S₃ = @lift Float64.(S_lego[:, :, $n + 1])
ζ₃ = @lift Float64.(ζ_lego[:, :, $n + 1]) ./ f₀

fig = Figure(size = (2200, 900), fontsize = 18)

title = @lift @sprintf("Barotropic instability of a 1 m s⁻¹ jet  —  day %.2f", times[$n + 1] / 86400)
Label(fig[0, 1:3], title, fontsize = 26, font = :bold)

Label(fig[1, 1], "NEMO 4.2\nUBS momentum + bilaplacian viscosity, UBS tracer", tellwidth = false)
Label(fig[1, 2], "Oceananigans 0.113\nWENO9 vector-invariant momentum, WENO9 tracer", tellwidth = false)
Label(fig[1, 3], "legoESM 1.0\nWENO9 vector-invariant momentum, WENO7 tracer", tellwidth = false)

axis_kw = (aspect = DataAspect(), xticklabelsvisible = false, yticklabelsvisible = false,
           xticksvisible = false, yticksvisible = false)

axS = [Axis(fig[2, j]; axis_kw...) for j in 1:3]
axζ = [Axis(fig[3, j]; axis_kw...) for j in 1:3]

S_kw = (colormap = :magma, colorrange = (30, 35))
ζ_kw = (colormap = :balance, colorrange = (-1, 1))

hmS = heatmap!(axS[1], xᶜ, yᶜ, S₁; S_kw...)
heatmap!(axS[2], xᶜ_ocnn .* km, yᶜ_ocnn .* km, S₂; S_kw...)
heatmap!(axS[3], xᶜ_lego, yᶜ_lego, S₃; S_kw...)
hmζ = heatmap!(axζ[1], xᶠ, yᶠ, ζ₁; ζ_kw...)
heatmap!(axζ[2], xᶠ_ocnn .* km, yᶠ_ocnn .* km, ζ₂; ζ_kw...)
heatmap!(axζ[3], xᶠ_lego, yᶠ_lego, ζ₃; ζ_kw...)

Colorbar(fig[2, 4], hmS, label = "Salinity dye (g kg⁻¹)")
Colorbar(fig[3, 4], hmζ, label = "Vertical vorticity ζ / f")

Label(fig[4, 1:3], "2005 × 995 km periodic channel, 5 km grid, f-plane at 38.5ᵒN, 1000 m deep, no closure except NEMO's", fontsize = 15)

rowgap!(fig.layout, 8)
colgap!(fig.layout, 12)
resize_to_layout!(fig)

record(fig, output, 1:Nt; framerate = 15) do nn
    n[] = nn
end

close(lego)

@info "Saved $output with $Nt frames"
