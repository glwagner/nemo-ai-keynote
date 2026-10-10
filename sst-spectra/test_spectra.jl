# Validation of spectra.jl on synthetic isotropic Gaussian random fields.
#
#   julia --startup-file=no --project=sst-spectra sst-spectra/test_spectra.jl
#
# Fields live on a 1/48° (≈ 0.02°) longitude-latitude grid, 8° × 4° centered on 30°N, with a
# prescribed 1-D power-law spectrum. Checks: slope recovery, Parseval, white-noise floor and
# correction, cloud masking, and block-averaging to a 1/12° model grid. Writes test_spectra.png.

using CairoMakie
using FFTW
using Random
using Statistics
using Printf

include(joinpath(@__DIR__, "spectra.jl"))

const rng = MersenneTwister(2026)
failures = String[]

function check(name, ok, detail)
    status = ok ? "PASS" : "FAIL"
    println(@sprintf("%-4s %-52s %s", status, name, detail))
    ok || push!(failures, name)
    return ok
end

#####
##### Synthetic fields
#####

const Δ° = 1 / 48
const φ₀ = 30.0
λ = range(-70 + Δ° / 2, -62 - Δ° / 2, step = Δ°) |> collect
φ = range(φ₀ - 2 + Δ° / 2, φ₀ + 2 - Δ° / 2, step = Δ°) |> collect
const Δx = R_EARTH * cosd(φ₀) * deg2rad(Δ°) # km, at the central latitude
const Δy = R_EARTH * deg2rad(Δ°)
nx, ny = length(λ), length(φ)

"""
Isotropic Gaussian random field with 1-D transect spectrum ∝ k^(-slope). The 2-D spectral
density is ∝ κ^(-slope-1), since integrating over the transverse wavenumber adds one power.
Generated in physical wavenumbers with grid spacings Δx, Δy (km) and scaled to standard deviation `σ`.
"""
function synthetic_field(nx, ny, Δx, Δy, slope; σ = 1.0)
    kx = fftfreq(nx, 1 / Δx)
    ky = fftfreq(ny, 1 / Δy)
    κ = sqrt.(kx .^ 2 .+ (ky') .^ 2)
    amplitude = κ .^ (-(slope + 1) / 2)
    amplitude[1, 1] = 0
    T = real(ifft(randn(rng, ComplexF64, nx, ny) .* amplitude))
    return T .* (σ / std(T))
end

"""Blobby cloud mask covering `fraction` of the domain: thresholded Gaussian-smoothed white noise."""
function cloud_mask(nx, ny, Δx, Δy, ℓ, fraction)
    kx = fftfreq(nx, 1 / Δx)
    ky = fftfreq(ny, 1 / Δy)
    κ² = kx .^ 2 .+ (ky') .^ 2
    smooth = real(ifft(fft(randn(rng, nx, ny)) .* exp.(-(2π)^2 .* κ² .* ℓ^2 / 2)))
    return smooth .> quantile(vec(smooth), 1 - fraction)
end

"""Block-average `T` over `n × n` cells (like a coarser model grid); returns the field and its coordinates."""
function coarsen(T, λ, φ, n)
    nx, ny = size(T) .÷ n
    Tc = [mean(@view T[(i-1)*n+1:i*n, (j-1)*n+1:j*n]) for i in 1:nx, j in 1:ny]
    λc = [mean(@view λ[(i-1)*n+1:i*n]) for i in 1:nx]
    φc = [mean(@view φ[(j-1)*n+1:j*n]) for j in 1:ny]
    return Tc, λc, φc
end

"""
Slope of the exact 1-D transect spectrum implied by the prescribed 2-D density over `krange`:
the finite transverse Nyquist truncates the integral over the transverse wavenumber, which
steepens the transect spectrum slightly below the nominal power law near the grid scale.
"""
function reference_slope(nx, ny, Δx, Δy, slope, krange)
    kx = fftfreq(nx, 1 / Δx)
    ky = fftfreq(ny, 1 / Δy)
    κ = sqrt.(kx .^ 2 .+ (ky') .^ 2)
    density = κ .^ (-(slope + 1))
    density[1, 1] = 0
    P₁ = vec(sum(density, dims = 2))
    return fit_slope(kx, P₁, krange)[1]
end

nimages = 8
kmin, knyq = common_wavenumbers(λ, φ, 4)
edges = wavenumber_bins(0.9kmin, 1 / 2Δx; per_decade = 10, Δk_min = kmin) # start below the longest segment's first mode
inertial = (1 / 80, 1 / 10)                                                  # fit range, wavelengths 10–80 km

#####
##### 0. Taper choice
#####

println("0. Taper comparison on full periodic rows of a k⁻³ field (slope over the fit range)")
let T = synthetic_field(nx, ny, Δx, Δy, 3), kref = reference_slope(nx, ny, Δx, Δy, 3, inertial)
    for (name, window) in (("Hann", hann), ("Tukey α = 0.1", tukey(0.1)), ("Tukey α = 0.5", tukey(0.5)))
        P = mean(j -> power_spectrum(T[:, j], Δx; window)[2], 1:ny)
        k = power_spectrum(T[:, 1], Δx)[1]
        println(@sprintf("     %-14s %.3f   (exact 1-D spectrum: %.3f)", name, fit_slope(k, P, inertial)[1], kref))
    end
end

#####
##### 1. Slopes and Parseval
#####

println("\n1. Power-law slopes (k⁻², k⁻³), 8 images of 8° × 4° at 1/48°")
results = Dict{Int, Any}()
fields = Dict{Int, Vector{Matrix{Float64}}}()
for slope in (2, 3)
    accs = spectrum_accumulators(edges)
    fields[slope] = [synthetic_field(nx, ny, Δx, Δy, slope) for _ in 1:nimages]
    for (n, T) in enumerate(fields[slope])
        image_spectra!(accs, T, λ, φ; group = n)
    end
    s = Dict(d => fit_slope(mean_spectrum(accs[d]).k, mean_spectrum(accs[d]).P_T, inertial)[1]
             for d in (:zonal, :meridional, :combined))
    g = fit_slope(mean_spectrum(accs.combined).k, mean_spectrum(accs.combined).P_∇T, inertial)[1]
    ref = reference_slope(nx, ny, Δx, Δy, slope, inertial)
    results[slope] = (; accs, slopes = s, gradient_slope = g)
    for d in (:zonal, :meridional, :combined)
        check("k⁻$slope slope, $d", abs(s[d] - ref) < 0.1, @sprintf("%.3f (exact 1-D spectrum %.3f)", s[d], ref))
    end
    check("k⁻$slope gradient slope (expect $(2 - slope))", abs(g - (2 + ref)) < 0.1, @sprintf("%.3f", g))
    println("     segments: zonal $(accs.zonal.nsegments), meridional $(accs.meridional.nsegments)")
end

# Parseval: (a) exact identity per segment; (b) the mean tapered variance matches the mean
# raw detrended variance; (c) the integral of the binned zonal spectrum matches too.
segments = extract_segments(fields[2][1], λ, φ)
identity_error = maximum(segments) do s
    k, P = segment_spectrum(s)
    w = hann(length(s))
    y = w .* detrend(s.values)
    abs(sum(P) * (k[2] - k[1]) - var(y, corrected = false) / mean(abs2, w)) / var(y, corrected = false)
end
check("Parseval identity per segment", identity_error < 1e-10, @sprintf("max relative error %.1e", identity_error))

zonal = filter(s -> s.direction == :zonal, segments)
raw_variance = mean(s -> var(detrend(s.values), corrected = false), zonal)
tapered_variance = mean(zonal) do s
    k, P = segment_spectrum(s)
    sum(P) * (k[2] - k[1])
end
check("Parseval, tapered vs raw segment variance", abs(tapered_variance / raw_variance - 1) < 0.05,
      @sprintf("ratio %.3f", tapered_variance / raw_variance))

acc_zonal = SpectrumAccumulator(edges)
foreach(s -> accumulate!(acc_zonal, s), zonal)
captured = sum(acc_zonal.sum_T) / sum(s -> sum(segment_spectrum(s)[2]), zonal) # every estimate must land in a bin
check("Parseval, spectral power captured by the bins", abs(captured - 1) < 1e-3, @sprintf("fraction %.5f", captured))

# Low-wavenumber bias from the taper's main lobe: bin-averaged zonal spectrum of the k⁻² fields
# relative to the exact 1-D spectrum, as a function of k/Δk (Δk = 1/segment length)
let kx = fftfreq(nx, 1 / Δx), ky = fftfreq(ny, 1 / Δy)
    κ = sqrt.(kx .^ 2 .+ (ky') .^ 2)
    density = κ .^ -3
    density[1, 1] = 0
    kex, Pex = kx[2:nx÷2+1], vec(sum(density, dims = 2))[2:nx÷2+1]
    exact(k) = exp(let i = clamp(searchsortedlast(kex, k), 1, length(kex) - 1)
                       log(Pex[i]) + (log(k) - log(kex[i])) / (log(kex[i+1]) - log(kex[i])) * (log(Pex[i+1]) - log(Pex[i]))
                   end)
    mz = mean_spectrum(results[2].accs.zonal)
    ratio = mz.P_T ./ exact.(mz.k)
    ratio ./= mean(ratio[inertial[1] .<= mz.k .<= inertial[2]])
    Δk = mean(s -> 1 / segment_length(s), zonal)
    println("     toolkit / exact 1-D spectrum (k⁻², zonal), normalized over the fit range:")
    for (k, r) in zip(mz.k, ratio)
        isfinite(r) && println(@sprintf("       k/Δk = %5.1f  k = %.4f cycles/km  ratio %.3f", k / Δk, k, r))
    end
end

# Block-bootstrap confidence interval over the 8 images
ci = bootstrap_ci(results[2].accs.combined; rng)
m2 = mean_spectrum(results[2].accs.combined)
sel = inertial[1] .<= m2.k .<= inertial[2]
halfwidth = mean((ci.P_T[2][sel] .- ci.P_T[1][sel]) ./ 2m2.P_T[sel])
se = standard_error(results[2].accs.combined)
println(@sprintf("     95%% bootstrap CI half-width in the inertial range: %.1f%% of P_T (naive SE: %.1f%%)",
                 100halfwidth, 100mean(se.P_T[sel] ./ m2.P_T[sel])))

#####
##### 2. White noise
#####

println("\n2. White noise σ = 0.1 K added to k⁻³ fields with σ_T = 1 K")
σ = 0.1
noisy = spectrum_accumulators(edges)
for (n, T) in enumerate(fields[3])
    image_spectra!(noisy, T .+ σ .* randn(rng, size(T)), λ, φ; group = n)
end
noise_levels = Dict{Symbol, Float64}()
for d in (:zonal, :meridional)
    N = noise_floor(noisy[d])
    expected = 2σ^2 * mean_Δx(noisy[d])
    noise_levels[d] = N
    check("noise floor, $d (expect 2σ²Δx)", abs(N / expected - 1) < 0.1,
          @sprintf("%.4f vs %.4f K² (cycle/km)⁻¹, ratio %.3f", N, expected, N / expected))
end
raw_slope = fit_slope(mean_spectrum(noisy.zonal).k, mean_spectrum(noisy.zonal).P_T, inertial)[1]
corrected = noise_corrected(noisy.zonal, noise_levels[:zonal])
unflagged = .!corrected.flagged
noise_free = mean_spectrum(results[3].accs.zonal)
fit_bins = unflagged .& (inertial[1] .<= corrected.k .<= inertial[2])
corrected_slope = fit_slope(corrected.k[unflagged], corrected.P_T[unflagged], inertial)[1]
noise_free_slope = fit_slope(noise_free.k[fit_bins], noise_free.P_T[fit_bins], inertial)[1]
restored = corrected.P_T[fit_bins] ./ noise_free.P_T[fit_bins]
check("noise-corrected zonal slope (unflagged bins)", abs(corrected_slope - noise_free_slope) < 0.1,
      @sprintf("raw %.2f → corrected %.3f (noise-free, same bins %.3f); %d of %d bins flagged (> 50%% noise)",
               raw_slope, corrected_slope, noise_free_slope, count(corrected.flagged), nbins(noisy.zonal)))
check("noise-corrected / noise-free spectrum", maximum(abs, restored .- 1) < 0.1,
      @sprintf("range %.3f–%.3f over %d unflagged bins", extrema(restored)..., count(fit_bins)))

#####
##### 3. Cloud mask
#####

println("\n3. Blobby cloud mask covering 60%, k⁻² fields")
nmasked = 32
cloudy_fields = [synthetic_field(nx, ny, Δx, Δy, 2) for _ in 1:nmasked]
masks = [cloud_mask(nx, ny, Δx, Δy, 60.0, 0.6) for _ in 1:nmasked]
println(@sprintf("     %d images, cloud fraction %.2f, blob scale 60 km", nmasked, mean(mean, masks)))
masked = spectrum_accumulators(edges)
clear = spectrum_accumulators(edges)
for (n, T) in enumerate(cloudy_fields)
    image_spectra!(masked, ifelse.(masks[n], NaN, T), λ, φ; group = n)
    image_spectra!(clear, T, λ, φ; group = n)
end
mm, mc = mean_spectrum(masked.combined), mean_spectrum(clear.combined)
ratio = mm.P_T[sel] ./ mc.P_T[sel]
masked_slope = fit_slope(mm.k, mm.P_T, inertial)[1]
clear_slope = fit_slope(mc.k, mc.P_T, inertial)[1]
check("masked / clear spectrum ratio", abs(mean(ratio) - 1) < 0.05 && maximum(abs, ratio .- 1) < 0.15,
      @sprintf("mean %.3f, range %.3f–%.3f", mean(ratio), extrema(ratio)...))
check("masked slope", abs(masked_slope - clear_slope) < 0.1, @sprintf("%.3f (clear %.3f)", masked_slope, clear_slope))
println(@sprintf("     4° segments: %d of %d clear (zonal %d, meridional %d)", masked.combined.nsegments,
                 clear.combined.nsegments, masked.zonal.nsegments, masked.meridional.nsegments))
for L in (1, 2, 3)
    yield = sum(n -> length(extract_segments(ifelse.(masks[n], NaN, cloudy_fields[n]), λ, φ; segment_degrees = L)), 1:nmasked) /
            sum(n -> length(extract_segments(cloudy_fields[n], λ, φ; segment_degrees = L)), 1:nmasked)
    println(@sprintf("     %d° segments: %.1f%% clear", L, 100yield))
end

#####
##### 4. Coarse-grained to 1/12°
#####

println("\n4. Block-averaged (4 × 4) to 1/12°, k⁻² fields")
coarse = spectrum_accumulators(edges)
for (n, T) in enumerate(fields[2])
    Tc, λc, φc = coarsen(T, λ, φ, 4)
    image_spectra!(coarse, Tc, λc, φc; group = n)
end
knyq_coarse = 1 / (2 * 4Δy)
mcoarse = mean_spectrum(coarse.combined)
mfine = mean_spectrum(results[2].accs.combined)
coarse_range = (1 / 100, 0.55knyq_coarse)
coarse_slope = fit_slope(mcoarse.k, mcoarse.P_T, coarse_range)[1]
fine_slope = fit_slope(mfine.k, mfine.P_T, coarse_range)[1]
println(@sprintf("     slopes over %.4f–%.4f cycles/km: coarse %.3f, fine field on the same bins %.3f", coarse_range..., coarse_slope, fine_slope))
# Block averaging over n × n cells multiplies the 2-D spectrum by sinc²(π kₓ nΔx) sinc²(π k_y nΔy); the
# transverse factor also lowers the 1-D transect spectrum. Expected zonal ratio (ignoring aliasing,
# small below ~0.6 of the coarse Nyquist) from the prescribed κ⁻³ density:
sinc²(x) = x == 0 ? 1.0 : (sin(x) / x)^2
let mz = mean_spectrum(coarse.zonal), mzf = mean_spectrum(results[2].accs.zonal)
    ky = fftfreq(ny, 1 / Δy)
    transfer(kx) = sum(@. (kx^2 + ky^2)^(-3/2) * sinc²(π * kx * 4Δx) * sinc²(π * ky * 4Δy)) / sum(@. (kx^2 + ky^2)^(-3/2))
    sel = isfinite.(mz.P_T) .& (coarse_range[1] .<= mz.k .<= 0.6knyq_coarse)
    r = mz.P_T[sel] ./ mzf.P_T[sel] ./ transfer.(mz.k[sel])
    check("coarse / fine matches the block-mean transfer", maximum(abs, r .- 1) < 0.1,
          @sprintf("observed / expected %.3f–%.3f over %d bins up to 0.6 Nyquist", extrema(r)..., count(sel)))
end
near_nyquist = findlast(k -> isfinite(mcoarse.P_T[findfirst(==(k), mcoarse.k)]) && k <= knyq_coarse, mcoarse.k)
rolloff = mcoarse.P_T[near_nyquist] / mfine.P_T[near_nyquist]
check("roll-off at the coarse Nyquist", 0.3 < rolloff < 0.9, @sprintf("coarse / fine = %.2f at k = %.3f", rolloff, mcoarse.k[near_nyquist]))
println("     segments: zonal $(coarse.zonal.nsegments), meridional $(coarse.meridional.nsegments) of $(4 * 48) points")

#####
##### 5. Convergence of the slope with the number of segments
#####

println("\n5. Slope scatter versus number of segments (k⁻², single image, random subsets)")
all_segments = extract_segments(fields[2][1], λ, φ)
nsub = [5, 10, 20, 50, 100, 200, 400]
slope_spread = map(nsub) do n
    slopes = map(1:40) do _
        acc = SpectrumAccumulator(edges)
        foreach(s -> accumulate!(acc, s), rand(rng, all_segments, n))
        fit_slope(mean_spectrum(acc).k, mean_spectrum(acc).P_T, inertial)[1]
    end
    (mean(slopes), std(slopes))
end
for (n, (μ, s)) in zip(nsub, slope_spread)
    println(@sprintf("     %4d segments: slope %.2f ± %.2f", n, μ, s))
end

#####
##### Figure
#####

set_theme!(fontsize = 15)
colors = (blue = "#2a78d6", orange = "#eb6834", aqua = "#1baf7a", yellow = "#eda100", violet = "#6250d6", grey = "#8a8984")
fig = Figure(size = (1600, 950))

logaxis(pos, title; ylabel = "P_T (K² per cycle/km)") =
    Axis(fig[pos...]; xscale = log10, yscale = log10, title, xlabel = "k (cycles/km)", ylabel,
         xminorticksvisible = true, xminorgridvisible = true, titlealign = :left)
reference!(ax, k, slope, level, kref; kwargs...) =
    lines!(ax, k, level .* (k ./ kref) .^ slope; linestyle = :dash, color = colors.grey, linewidth = 1.5, kwargs...)
kplot(m) = m.k[isfinite.(m.P_T)]
finite(v, m) = v[isfinite.(m.P_T)]
vspan_fit!(ax) = vspan!(ax, inertial...; color = (:black, 0.05))

# A. P_T for both slopes, zonal and meridional
axA = logaxis((1, 1), "A. SST spectra: zonal and meridional, k⁻² and k⁻³ fields")
vspan_fit!(axA)
for (slope, c) in ((2, colors.blue), (3, colors.orange))
    accs = results[slope].accs
    mz, mm_ = mean_spectrum(accs.zonal), mean_spectrum(accs.meridional)
    lines!(axA, kplot(mz), finite(mz.P_T, mz); color = c, linewidth = 2, label = "k⁻$slope zonal")
    lines!(axA, kplot(mm_), finite(mm_.P_T, mm_); color = c, linewidth = 2, linestyle = :dot, label = "k⁻$slope meridional")
    kref = 0.03
    level = mz.P_T[argmin(abs.(mz.k .- kref))]
    reference!(axA, kplot(mz), -slope, 1.5level, kref)
    cib = bootstrap_ci(accs.combined; rng)
    band!(axA, kplot(mz), finite(cib.P_T[1], mz), finite(cib.P_T[2], mz); color = (c, 0.2))
end
axislegend(axA, position = :rt)
text!(axA, 0.0035, 2e-4; text = "dashed: expected slope\nband: 95% block bootstrap over 8 images\nshaded: fit range", fontsize = 12)

# B. Gradient spectra
axB = logaxis((1, 2), "B. Gradient spectra P_∇T = (2πk)² P_T"; ylabel = "P_∇T ((K/km)² per cycle/km)")
vspan_fit!(axB)
for (slope, c) in ((2, colors.blue), (3, colors.orange))
    mcb = mean_spectrum(results[slope].accs.combined)
    lines!(axB, kplot(mcb), finite(mcb.P_∇T, mcb); color = c, linewidth = 2, label = @sprintf("k⁻%d field, fitted slope %.2f", slope, results[slope].gradient_slope))
    kref = 0.03
    reference!(axB, kplot(mcb), 2 - slope, 1.5mcb.P_∇T[argmin(abs.(mcb.k .- kref))], kref)
end
axislegend(axB, position = :lt)

# C. Noise
axC = logaxis((1, 3), "C. White noise σ = 0.1 K on a k⁻³ field (zonal)")
vspan_fit!(axC)
mn = mean_spectrum(noisy.zonal)
mt = mean_spectrum(results[3].accs.zonal)
lines!(axC, kplot(mt), finite(mt.P_T, mt); color = colors.grey, linewidth = 2, label = "noise-free")
lines!(axC, kplot(mn), finite(mn.P_T, mn); color = colors.orange, linewidth = 2, label = @sprintf("noisy, raw slope %.2f", raw_slope))
good = isfinite.(corrected.P_T) .& (corrected.P_T .> 0)
scatterlines!(axC, corrected.k[good], corrected.P_T[good]; color = colors.blue, linewidth = 2, markersize = 7,
              label = @sprintf("corrected, slope %.2f", corrected_slope))
scatter!(axC, corrected.k[good .& corrected.flagged], corrected.P_T[good .& corrected.flagged]; color = :white, strokecolor = colors.blue, strokewidth = 2, markersize = 9, label = "flagged (> 50% noise)")
hlines!(axC, [2σ^2 * mean_Δx(noisy.zonal)]; color = colors.grey, linestyle = :dash, label = "2σ²Δx")
hlines!(axC, [noise_levels[:zonal]]; color = colors.violet, linestyle = :dashdot, label = "estimated floor")
axislegend(axC, position = :lb)

# D. Cloud mask
axD = logaxis((2, 1), @sprintf("D. 60%% blobby cloud mask (%d images): %d of %d segments clear", nmasked, masked.combined.nsegments, clear.combined.nsegments))
vspan_fit!(axD)
lines!(axD, kplot(mc), finite(mc.P_T, mc); color = colors.grey, linewidth = 3, label = "no mask")
lines!(axD, kplot(mm), finite(mm.P_T, mm); color = colors.aqua, linewidth = 2, label = @sprintf("clear segments only, slope %.2f", masked_slope))
axislegend(axD, position = :rt)
axDr = Axis(fig[2, 1]; xscale = log10, width = Relative(0.38), height = Relative(0.26), halign = 0.12, valign = 0.1,
            xlabel = "k", ylabel = "masked / clear", xticklabelsize = 11, yticklabelsize = 11, xlabelsize = 12, ylabelsize = 12)
lines!(axDr, kplot(mm), finite(mm.P_T ./ mc.P_T, mm); color = colors.aqua)
hlines!(axDr, [1.0]; color = colors.grey, linestyle = :dash)
ylims!(axDr, 0.7, 1.3)

# E. Coarse-grained
axE = logaxis((2, 2), "E. Block-averaged to 1/12° (48-point segments)")
lines!(axE, kplot(mfine), finite(mfine.P_T, mfine); color = colors.grey, linewidth = 3, label = "1/48° field")
lines!(axE, kplot(mcoarse), finite(mcoarse.P_T, mcoarse); color = colors.violet, linewidth = 2, label = @sprintf("1/12° block mean, slope %.2f", coarse_slope))
vlines!(axE, [knyq_coarse]; color = colors.violet, linestyle = :dash, label = "1/12° Nyquist")
vspan!(axE, coarse_range...; color = (:black, 0.05))
reference!(axE, kplot(mfine), -2, 1.5mfine.P_T[argmin(abs.(mfine.k .- 0.03))], 0.03)
axislegend(axE, position = :rt)

# F. Convergence
axF = Axis(fig[2, 3]; xscale = log10, title = "F. Fitted k⁻² slope vs number of segments (40 subsets)",
           xlabel = "segments", ylabel = "fitted slope", titlealign = :left)
hlines!(axF, [-2.0]; color = colors.grey, linestyle = :dash)
band!(axF, Float64.(collect(nsub)), first.(slope_spread) .- last.(slope_spread), first.(slope_spread) .+ last.(slope_spread); color = (colors.blue, 0.2))
scatterlines!(axF, Float64.(collect(nsub)), first.(slope_spread); color = colors.blue, markersize = 9)
text!(axF, 6, -2.0 + 0.3; text = "band: ±1 std over subsets", fontsize = 12)

Label(fig[0, :], "spectra.jl validation on synthetic isotropic fields (8° × 4° at 30°N, 4° segments, Hann taper)";
      fontsize = 20, font = :bold, tellwidth = false)
save(joinpath(@__DIR__, "test_spectra.png"), fig; px_per_unit = 1.5)

println("\nFigure: ", joinpath(@__DIR__, "test_spectra.png"))
if isempty(failures)
    println("All checks passed.")
else
    println("FAILED: ", join(failures, "; "))
    exit(1)
end
