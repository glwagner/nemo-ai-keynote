# One-dimensional horizontal wavenumber spectra of sea-surface temperature and its gradient
# from gappy fields on regular longitude-latitude grids. Module-free: `include("spectra.jl")`.
#
# Conventions
#   * Fields T[i, j] with i the longitude index and j the latitude index; NaN marks missing data.
#   * Wavenumber k in cycles/km. P_T(k) in K² per (cycle/km); P_∇T(k) = (2πk)² P_T(k) in
#     (K/km)² per (cycle/km).
#   * Spectra are one-sided with k = 0 excluded and normalized so that
#         Σ_k P_T(k) Δk = var(w ⋅ detrend(x)) / mean(w²),
#     with Δk = 1/(N Δx), w the taper and var the mean-square about the mean. White noise of
#     variance σ² therefore gives the flat level P_T = 2σ²Δx (detrending lowers this by ≈ (N-2)/N).
#   * Taper: Hann by default. Its sidelobes fall as k⁻³, which, after removing the linear trend,
#     keeps leakage from the energetic large scales below the k⁻² to k⁻³ SST spectra we expect
#     down to the Nyquist wavenumber. A Tukey taper keeps more variance but its k⁻² sidelobes
#     flatten steep spectra near the grid scale; `tukey(α)` is provided for comparison.

using FFTW
using Statistics
using Random
using LinearAlgebra: dot

const R_EARTH = 6371.0 # km

#####
##### Segments
#####

"""
A clear (fully finite) 1-D transect of a field.

`values` are the field samples, `Δx` the grid spacing in km, `direction` is `:zonal` or
`:meridional`, and `(λ, φ)` the longitude and latitude of the first sample.
"""
struct Segment
    values::Vector{Float64}
    Δx::Float64
    direction::Symbol
    λ::Float64
    φ::Float64
end

Base.length(s::Segment) = length(s.values)
segment_length(s::Segment) = length(s) * s.Δx # km

"""
    extract_segments(T, λ, φ; segment_degrees = 4)

Tile every row (zonal) and column (meridional) of `T[i, j]` into non-overlapping windows of
`segment_degrees`, starting at the first grid point, and return the windows that contain no
NaN as a vector of `Segment`s. Zonal spacing is R cosφ Δλ at the row's latitude; meridional
spacing is R Δφ.
"""
function extract_segments(T::AbstractMatrix, λ::AbstractVector, φ::AbstractVector; segment_degrees = 4.0)
    Δλ = abs(λ[2] - λ[1])
    Δφ = abs(φ[2] - φ[1])
    nλ = round(Int, segment_degrees / Δλ)
    nφ = round(Int, segment_degrees / Δφ)
    segments = Segment[]

    for j in eachindex(φ)
        Δx = R_EARTH * cosd(φ[j]) * deg2rad(Δλ)
        for i0 in 1:nλ:size(T, 1)-nλ+1
            v = @view T[i0:i0+nλ-1, j]
            all(isfinite, v) && push!(segments, Segment(collect(Float64, v), Δx, :zonal, λ[i0], φ[j]))
        end
    end

    Δy = R_EARTH * deg2rad(Δφ)
    for i in eachindex(λ), j0 in 1:nφ:size(T, 2)-nφ+1
        v = @view T[i, j0:j0+nφ-1]
        all(isfinite, v) && push!(segments, Segment(collect(Float64, v), Δy, :meridional, λ[i], φ[j0]))
    end

    return segments
end

"""
    common_wavenumbers(λ, φ, segment_degrees)

`(kmin, knyquist)` in cycles/km: the lowest wavenumber resolved by every segment of the box
(one cycle over the shortest segment, i.e. the zonal one at highest latitude) and the smallest
Nyquist wavenumber (set by the coarsest spacing).
"""
function common_wavenumbers(λ, φ, segment_degrees)
    Δλ = abs(λ[2] - λ[1])
    Δφ = abs(φ[2] - φ[1])
    cosφ = cosd(maximum(abs, φ))
    Lzonal = R_EARTH * cosφ * deg2rad(segment_degrees)
    Lmeridional = R_EARTH * deg2rad(segment_degrees)
    Δmax = max(R_EARTH * deg2rad(Δλ), R_EARTH * deg2rad(Δφ))
    return 1 / min(Lzonal, Lmeridional), 1 / (2Δmax)
end

#####
##### Per-segment spectrum
#####

"""Hann taper of length `N` (zeros one point outside each end, so no sample is discarded)."""
hann(N) = [sin(π * n / (N + 1))^2 for n in 1:N]

"""Tukey taper: flat with cosine ramps covering a fraction `α` of the segment."""
function tukey(α)
    return function (N)
        w = ones(N)
        m = max(1, round(Int, α * (N - 1) / 2))
        for n in 1:m
            w[n] = w[N+1-n] = 0.5 * (1 - cos(π * (n - 1) / m))
        end
        return w
    end
end

"""Remove a least-squares linear trend (and the mean) from `x`."""
function detrend(x::AbstractVector)
    N = length(x)
    n = (1:N) .- (N + 1) / 2
    x̄ = mean(x)
    b = dot(n, x .- x̄) / dot(n, n)
    return x .- x̄ .- b .* n
end

"""
    power_spectrum(x, Δx; window = hann)

One-sided power spectral density of the detrended, tapered series `x` with spacing `Δx` (km).
Returns `(k, P)` for k > 0 in cycles/km, with Σ P Δk = var(w ⋅ detrend(x)) / mean(w²).
"""
function power_spectrum(x::AbstractVector, Δx; window = hann)
    N = length(x)
    w = window(N)
    y = w .* detrend(x)
    Y = rfft(y)
    k = rfftfreq(N, 1 / Δx)
    P = 2 .* abs2.(Y) .* Δx ./ (N * mean(abs2, w))
    iseven(N) && (P[end] /= 2) # the Nyquist component appears once
    return k[2:end], P[2:end]
end

segment_spectrum(s::Segment; window = hann) = power_spectrum(s.values, s.Δx; window)

"""Gradient spectrum (K/km)² per (cycle/km) from the SST spectrum."""
gradient_spectrum(k, P) = (2π .* k) .^ 2 .* P

#####
##### Accumulation onto fixed wavenumber bins
#####

"""
    wavenumber_bins(kmin, kmax; per_decade = 10, Δk_min = 0)

Edges of log-spaced wavenumber bins spanning `[kmin, kmax]` (cycles/km), as close as possible to
`per_decade` bins per decade. Edges that would make a bin narrower than `Δk_min` are dropped, so
that with `Δk_min = 1/L` (L the segment length) every bin holds at least one estimate per segment;
without it, the lowest bins are narrower than the spectral resolution and sparsely, irregularly populated.
"""
function wavenumber_bins(kmin, kmax; per_decade = 10, Δk_min = 0)
    n = max(1, round(Int, per_decade * log10(kmax / kmin)))
    edges = 10 .^ range(log10(kmin), log10(kmax), length = n + 1)
    kept = [edges[1]]
    for e in edges[2:end-1]
        e - kept[end] >= Δk_min && push!(kept, e)
    end
    length(kept) > 1 && kmax - kept[end] < Δk_min && pop!(kept)
    push!(kept, kmax)
    return kept
end

"""Per-bin sums of the spectral estimates from one group (image) of segments."""
struct BinSums
    T::Vector{Float64}
    ∇::Vector{Float64}
    count::Vector{Int}
end

BinSums(n::Int) = BinSums(zeros(n), zeros(n), zeros(Int, n))

function add!(a::BinSums, b::BinSums)
    a.T .+= b.T
    a.∇ .+= b.∇
    a.count .+= b.count
    return a
end

"""
Running per-bin statistics of the SST spectrum `P_T` and gradient spectrum `P_∇T`.

Every spectral estimate (one wavenumber of one segment) whose k falls in a bin contributes one
sample; `count` is the number of samples. `groups` keeps per-group (image / time) sums for the
block bootstrap. `sum_k²` holds Σ (2πk)² of the samples, so that white-noise levels can be
converted to gradient-spectrum levels consistently with how `P_∇T` was accumulated.
"""
mutable struct SpectrumAccumulator
    edges::Vector{Float64}
    k::Vector{Float64}
    count::Vector{Int}
    sum_T::Vector{Float64}
    sumsq_T::Vector{Float64}
    sum_∇::Vector{Float64}
    sumsq_∇::Vector{Float64}
    sum_k²::Vector{Float64}
    groups::Dict{Any, BinSums}
    nsegments::Int
    sum_Δx::Float64
end

function SpectrumAccumulator(edges::AbstractVector)
    n = length(edges) - 1
    k = sqrt.(edges[1:end-1] .* edges[2:end])
    return SpectrumAccumulator(collect(Float64, edges), k, zeros(Int, n), zeros(n), zeros(n),
                               zeros(n), zeros(n), zeros(n), Dict{Any, BinSums}(), 0, 0.0)
end

nbins(acc::SpectrumAccumulator) = length(acc.k)
mean_Δx(acc::SpectrumAccumulator) = acc.sum_Δx / acc.nsegments

"""
    accumulate!(acc, k, P; group = nothing)

Add the spectral estimates `P(k)` of one segment to `acc`. Estimates outside the bin edges are
ignored. `group` labels the image for the block bootstrap.
"""
function accumulate!(acc::SpectrumAccumulator, k::AbstractVector, P::AbstractVector; group = nothing)
    g = group === nothing ? nothing : get!(() -> BinSums(nbins(acc)), acc.groups, group)
    for (kᵢ, Pᵢ) in zip(k, P)
        b = searchsortedlast(acc.edges, kᵢ)
        (1 <= b <= nbins(acc)) || continue
        κ² = (2π * kᵢ)^2
        G = κ² * Pᵢ
        acc.count[b] += 1
        acc.sum_T[b] += Pᵢ
        acc.sumsq_T[b] += Pᵢ^2
        acc.sum_∇[b] += G
        acc.sumsq_∇[b] += G^2
        acc.sum_k²[b] += κ²
        if g !== nothing
            g.count[b] += 1
            g.T[b] += Pᵢ
            g.∇[b] += G
        end
    end
    return acc
end

function accumulate!(acc::SpectrumAccumulator, s::Segment; window = hann, group = nothing)
    k, P = segment_spectrum(s; window)
    accumulate!(acc, k, P; group)
    acc.nsegments += 1
    acc.sum_Δx += s.Δx
    return acc
end

"""Merge `b` into `a` (same bin edges). Groups with the same label are summed."""
function Base.merge!(a::SpectrumAccumulator, b::SpectrumAccumulator)
    a.edges == b.edges || error("accumulators have different bin edges")
    a.count .+= b.count
    a.sum_T .+= b.sum_T
    a.sumsq_T .+= b.sumsq_T
    a.sum_∇ .+= b.sum_∇
    a.sumsq_∇ .+= b.sumsq_∇
    a.sum_k² .+= b.sum_k²
    for (key, g) in b.groups
        add!(get!(() -> BinSums(nbins(a)), a.groups, key), g)
    end
    a.nsegments += b.nsegments
    a.sum_Δx += b.sum_Δx
    return a
end

function Base.merge(a::SpectrumAccumulator, b::SpectrumAccumulator)
    c = SpectrumAccumulator(a.edges)
    merge!(c, a)
    merge!(c, b)
    return c
end

"""
    mean_spectrum(acc)

`(; k, P_T, P_∇T, count)`: bin-averaged SST and gradient spectra (NaN in empty bins).
"""
function mean_spectrum(acc::SpectrumAccumulator)
    n = replace(Float64.(acc.count), 0.0 => NaN)
    return (; k = acc.k, P_T = acc.sum_T ./ n, P_∇T = acc.sum_∇ ./ n, count = acc.count)
end

"""
    standard_error(acc)

`(; P_T, P_∇T)`: standard error of the bin means from the sample spread, treating every
spectral estimate as independent. Adjacent segments of one image are correlated, so this
understates the uncertainty; prefer `bootstrap_ci` when several images are available.
"""
function standard_error(acc::SpectrumAccumulator)
    n = replace(Float64.(acc.count), 0.0 => NaN)
    se(s, sq) = sqrt.(max.(sq ./ n .- (s ./ n) .^ 2, 0) ./ n)
    return (; P_T = se(acc.sum_T, acc.sumsq_T), P_∇T = se(acc.sum_∇, acc.sumsq_∇))
end

"""
    bootstrap_ci(acc; nboot = 1000, level = 0.95, rng = Random.default_rng())

Block-bootstrap confidence interval of the bin means: resample whole groups (images / times,
as labelled through `group` in `accumulate!`) with replacement, recompute the pooled mean, and
take the `(1-level)/2` and `(1+level)/2` quantiles. Returns `(; P_T, P_∇T)`, each a `(lower, upper)`
pair of vectors (NaN when fewer than two groups exist).
"""
function bootstrap_ci(acc::SpectrumAccumulator; nboot = 1000, level = 0.95, rng = Random.default_rng())
    groups = collect(values(acc.groups))
    n = nbins(acc)
    if length(groups) < 2
        @warn "bootstrap_ci needs at least two groups; returning NaN intervals"
        nan = fill(NaN, n)
        return (; P_T = (nan, nan), P_∇T = (nan, nan))
    end
    T = zeros(nboot, n)
    ∇ = zeros(nboot, n)
    sT, s∇, c = zeros(n), zeros(n), zeros(n)
    for b in 1:nboot
        sT .= 0; s∇ .= 0; c .= 0
        for _ in 1:length(groups)
            g = rand(rng, groups)
            sT .+= g.T; s∇ .+= g.∇; c .+= g.count
        end
        c[c .== 0] .= NaN
        T[b, :] .= sT ./ c
        ∇[b, :] .= s∇ ./ c
    end
    α = (1 - level) / 2
    q(A, p) = [all(isnan, @view A[:, j]) ? NaN : quantile(filter(!isnan, @view A[:, j]), p) for j in 1:n]
    return (; P_T = (q(T, α), q(T, 1 - α)), P_∇T = (q(∇, α), q(∇, 1 - α)))
end

#####
##### Noise floor
#####

"""
    noise_floor(acc; fraction = 0.2, krange = nothing)

White-noise level of `P_T` (K² per cycle/km), estimated as the count-weighted mean of the
bin-averaged spectrum over the highest `fraction` of the populated wavenumber range (linear in k),
or over `krange = (k₁, k₂)` if given. Assumes the signal spectrum is negligible there; a steep
signal reaching the Nyquist wavenumber biases the estimate high.
"""
function noise_floor(acc::SpectrumAccumulator; fraction = 0.2, krange = nothing)
    populated = acc.count .> 0
    if krange === nothing
        kmax = acc.edges[findlast(populated) + 1]
        krange = ((1 - fraction) * kmax, kmax)
    end
    sel = populated .& (krange[1] .<= acc.k .<= krange[2])
    any(sel) || error("no populated bins in the noise range")
    return sum(acc.sum_T[sel]) / sum(acc.count[sel])
end

"""Noise variance σ² (K²) implied by a flat level `N` of `P_T` at grid spacing `Δx` (km)."""
noise_variance(N, Δx) = N / (2Δx)

"""
    noise_corrected(acc, N; max_fraction = 0.5)

`(; k, P_T, P_∇T, flagged)`: bin-averaged spectra minus the white-noise contribution `N`
(for `P_∇T`, `N` times the bin mean of (2πk)²). `flagged` marks bins where the correction
exceeds `max_fraction` of the raw `P_T`.
"""
function noise_corrected(acc::SpectrumAccumulator, N; max_fraction = 0.5)
    m = mean_spectrum(acc)
    n = replace(Float64.(acc.count), 0.0 => NaN)
    N_∇ = N .* acc.sum_k² ./ n
    return (; k = m.k, P_T = m.P_T .- N, P_∇T = m.P_∇T .- N_∇, flagged = N .> max_fraction .* m.P_T)
end

#####
##### One image
#####

"""Zonal, meridional, and combined accumulators sharing the bin `edges`."""
spectrum_accumulators(edges) = (zonal = SpectrumAccumulator(edges),
                                meridional = SpectrumAccumulator(edges),
                                combined = SpectrumAccumulator(edges))

"""
    image_spectra!(accs, T, λ, φ; segment_degrees = 4, window = hann, group = nothing)

Extract clear segments of the image `T` and accumulate their spectra into
`accs = (; zonal, meridional, combined)`. Returns the number of segments used per direction.
"""
function image_spectra!(accs, T, λ, φ; segment_degrees = 4.0, window = hann, group = nothing)
    segments = extract_segments(T, λ, φ; segment_degrees)
    counts = Dict(:zonal => 0, :meridional => 0)
    for s in segments
        k, P = segment_spectrum(s; window)
        for acc in (accs[s.direction], accs.combined)
            accumulate!(acc, k, P; group)
            acc.nsegments += 1
            acc.sum_Δx += s.Δx
        end
        counts[s.direction] += 1
    end
    return (zonal = counts[:zonal], meridional = counts[:meridional])
end

"""Replace `missing` with NaN and convert to Float64."""
nanify(A) = Float64.(replace(A, missing => NaN))

#####
##### Fitting
#####

"""
    fit_slope(k, P, krange)

Least-squares slope and intercept of log10 P versus log10 k over `krange = (k₁, k₂)`,
skipping NaN bins. Returns `(slope, intercept)` with P ≈ 10^intercept k^slope.
"""
function fit_slope(k, P, krange)
    sel = (krange[1] .<= k .<= krange[2]) .& isfinite.(P) .& (P .> 0)
    x = log10.(k[sel])
    y = log10.(P[sel])
    x̄, ȳ = mean(x), mean(y)
    slope = dot(x .- x̄, y .- ȳ) / dot(x .- x̄, x .- x̄)
    return slope, ȳ - slope * x̄
end
