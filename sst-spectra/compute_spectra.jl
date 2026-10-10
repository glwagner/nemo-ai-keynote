# Wavenumber spectra of SST and |∇T| by region for the Mercator 1/12° analysis and
# native-resolution geostationary SST.
#
#   julia --project=sst-spectra sst-spectra/compute_spectra.jl [model|all] [--quality=Q] [--erode=N] [REGION ...]
#
# Satellite masking options:
#   --quality=Q  keep satellite pixels with quality_level ≥ Q (default: whatever was stored,
#                i.e. 5 for GOES; SEVIRI files store ≥ 3 and the default analysis uses 4)
#   --erode=N    also discard pixels within N pixels of any cloud, land, or bad pixel
#                (cloud-edge contamination), default 0
# Non-default options tag the output files, e.g. spectra_<region>_<variant>_<direction>_q5_e2.csv.
#
# Variants (all on the same per-region wavenumber bins, 4° segments, Hann window):
#   model        model SST, every fully ocean segment, every night
#   model_clear  model SST restricted to cells the satellite saw clear that night
#   obs          satellite SST at native resolution, fully clear segments
#   obs_coarse   satellite SST block-averaged onto the model grid (cells fully clear)
# Spectra are averaged over segments; 95% intervals are block bootstraps over nights.
# Results go to data/spectra_<region>_<variant>_<direction>[_<season>][_<tag>].csv.

using NCDatasets
using Dates
using TOML
using Printf
using Random
using Statistics

include(joinpath(@__DIR__, "spectra.jl"))

const dir = @__DIR__
const SEGMENT_DEGREES = 4.0
const SEASONS = Dict(12 => "DJF", 1 => "DJF", 2 => "DJF", 3 => "MAM", 4 => "MAM", 5 => "MAM",
                     6 => "JJA", 7 => "JJA", 8 => "JJA", 9 => "SON", 10 => "SON", 11 => "SON")

regions = TOML.parsefile(joinpath(dir, "regions.toml"))
options = Dict(split(a[3:end], "=")[1] => parse(Int, split(a, "=")[2]) for a in ARGS if startswith(a, "--"))
positional = [a for a in ARGS if !startswith(a, "--")]
mode = isempty(positional) ? "all" : positional[1]
keys_requested = length(positional) > 1 ? positional[2:end] :
    sort([k for k in keys(regions) if isfile(joinpath(dir, "data", "model_$k.nc"))])
const DEFAULT_QUALITY = Dict("goes" => 5, "seviri" => 4)
const ERODE = get(options, "erode", 0)
tag = join([haskey(options, "quality") ? "q$(options["quality"])" : "",
            ERODE > 0 ? "e$ERODE" : ""], "_") |> t -> strip(t, '_')
suffix_tag = isempty(tag) ? "" : "_" * tag

read_grid(ds) = (Float64.(ds["longitude"][:]), Float64.(ds["latitude"][:]))

"""Set to NaN every pixel within `n` pixels (Chebyshev distance) of a non-finite pixel."""
function erode(T, n)
    n == 0 && return T
    bad = .!isfinite.(T)
    near = similar(bad)
    for j in axes(T, 2), i in axes(T, 1) # separable max filter: rows then columns
        near[i, j] = any(@view bad[max(1, i - n):min(end, i + n), j])
    end
    out = copy(T)
    for j in axes(T, 2), i in axes(T, 1)
        any(@view near[i, max(1, j - n):min(end, j + n)]) && (out[i, j] = NaN)
    end
    return out
end

function satellite_sst(obs, n, min_quality)
    T = nanify(obs["sst"][:, :, n])
    if haskey(obs, "quality_level")
        q = obs["quality_level"][:, :, n]
        T[coalesce.(q .< min_quality, true)] .= NaN
    end
    return erode(T, ERODE)
end

"""Block-average a native-resolution field onto the model cells that contain it; a model cell
is valid only if every native pixel inside it is finite."""
function coarsen(T, λ, φ, λm, φm)
    Δλ, Δφ = λm[2] - λm[1], φm[2] - φm[1]
    S = zeros(length(λm), length(φm))
    C = zeros(Int, size(S))
    N = zeros(Int, size(S))
    ii = [round(Int, (x - λm[1]) / Δλ) + 1 for x in λ]
    jj = [round(Int, (y - φm[1]) / Δφ) + 1 for y in φ]
    for j in eachindex(φ), i in eachindex(λ)
        a, b = ii[i], jj[j]
        (1 <= a <= size(S, 1) && 1 <= b <= size(S, 2)) || continue
        N[a, b] += 1
        if isfinite(T[i, j])
            S[a, b] += T[i, j]
            C[a, b] += 1
        end
    end
    return [N[c] > 0 && C[c] == N[c] ? S[c] / C[c] : NaN for c in CartesianIndices(S)]
end

function write_spectrum(path, acc)
    m = mean_spectrum(acc)
    ci = bootstrap_ci(acc; nboot = 500, rng = MersenneTwister(1))
    open(path, "w") do io
        println(io, "k,P_T,P_T_lo,P_T_hi,P_gradT,P_gradT_lo,P_gradT_hi,count,nsegments,mean_dx_km,ngroups")
        Δx̄ = acc.nsegments > 0 ? acc.sum_Δx / acc.nsegments : NaN
        for b in eachindex(m.k)
            @printf(io, "%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%d,%d,%.4f,%d\n", m.k[b], m.P_T[b], ci.P_T[1][b], ci.P_T[2][b],
                    m.P_∇T[b], ci.P_∇T[1][b], ci.P_∇T[2][b], m.count[b], acc.nsegments, Δx̄, length(acc.groups))
        end
    end
end

for key in keys_requested
    r = regions[key]
    model = NCDataset(joinpath(dir, "data", "model_$key.nc"))
    λm, φm = read_grid(model)
    model_times = model["time"][:]

    with_obs = mode == "all" && isfile(joinpath(dir, "data", "obs_$key.nc"))
    if with_obs
        obs = NCDataset(joinpath(dir, "data", "obs_$key.nc"))
        λo, φo = read_grid(obs)
        obs_index = Dict(t => n for (n, t) in enumerate(obs["time"][:]))
        min_quality = get(options, "quality", DEFAULT_QUALITY[r["satellite"]])
        kmin, kmax = common_wavenumbers(λo, φo, SEGMENT_DEGREES)
    else
        kmin, kmax = common_wavenumbers(λm, φm, SEGMENT_DEGREES)
    end
    edges = wavenumber_bins(kmin, kmax; per_decade = 12, Δk_min = kmin)

    variants = with_obs ? ("model", "model_clear", "obs", "obs_coarse") : ("model",)
    periods = ("annual", "DJF", "MAM", "JJA", "SON")
    accs = Dict((v, p) => spectrum_accumulators(edges) for v in variants, p in periods)

    for (n, t) in enumerate(model_times)
        season = SEASONS[month(t)]
        fields = Dict("model" => nanify(model["sst"][:, :, n]))
        if with_obs
            haskey(obs_index, t) || continue
            To = satellite_sst(obs, obs_index[t], min_quality)
            fields["obs"] = To
            fields["obs_coarse"] = coarsen(To, λo, φo, λm, φm)
            fields["model_clear"] = ifelse.(isfinite.(fields["obs_coarse"]), fields["model"], NaN)
        end
        for v in variants
            λ, φ = v == "obs" ? (λo, φo) : (λm, φm)
            for p in ("annual", season)
                image_spectra!(accs[(v, p)], fields[v], λ, φ; segment_degrees = SEGMENT_DEGREES, group = n)
            end
        end
    end

    for v in variants, p in periods, d in (:zonal, :meridional, :combined)
        acc = accs[(v, p)][d]
        acc.nsegments == 0 && continue
        suffix = (p == "annual" ? "" : "_$p") * suffix_tag
        write_spectrum(joinpath(dir, "data", "spectra_$(key)_$(v)_$(d)$(suffix).csv"), acc)
    end
    summary = join(["$v: $(accs[(v, "annual")].combined.nsegments)" for v in variants], ", ")
    println("$key$suffix_tag segments — $summary")
    close(model)
    with_obs && close(obs)
end
