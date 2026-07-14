# Pure numeric WASM kernel — no DataFrames/Distributions/Turing/strings in hot path.
# Shared by native reference tests and WasmTarget AOT compilation.
#
# Flat buffer ABI (all Float64 unless noted):
#   INPUT  layout (worker packs this once per generation):
#     [0]      schema_version
#     [1]      n_films
#     [2]      n_draws
#     [3]      seed (as Float64; truncated to UInt64)
#     [4]      η_order
#     [5]      σ_order
#     [6]      n_overrides
#     then per film (11 values):
#       μ_logO, σ_logO, μ_logit_d, σ_logit_d, t_cut, banked, t_now,
#       theaters_or_-1, released_01, n_intervals, pad
#     then packed intervals (4 each): t_start, t_end, interval_gross, pad
#     then overrides (2 each): film_index (0-based), opening_m
#
#   OUTPUT layout:
#     [0]      status (0 ok, nonzero error code)
#     [1]      n_films
#     [2]      n_draws
#     [3]      elapsed_hint (0 in kernel; filled by host)
#     then G flattened column-major: G[film + n_films*draw]

module SMWKernel

export KERNEL_SCHEMA, spike_kernel!, run_simulation!

const KERNEL_SCHEMA = 1.0

@inline logistic(x::Float64) = 1.0 / (1.0 + exp(-x))

@inline function curve_factor(d::Float64, t::Float64)::Float64
    t <= 0.0 && return 0.0
    if abs(d - 1.0) < 1e-12
        return t
    end
    return -expm1(t * log(d)) / (1.0 - d)
end

@inline function interval_factor(d::Float64, t0::Float64, t1::Float64)::Float64
    t1 <= t0 && return 0.0
    return curve_factor(d, t1) - curve_factor(d, t0)
end

@inline function remaining_factor(d::Float64, t_pin::Float64, t_cut::Float64)::Float64
    t_cut <= t_pin && return 0.0
    d = clamp(d, 1e-9, 1.0 - 1e-9)
    num = exp(t_pin * log(d)) - exp(t_cut * log(d))
    den = 1.0 - exp(t_pin * log(d))
    den <= 0.0 && return 0.0
    return max(num / den, 0.0)
end

@inline function season_total_k(
    O::Float64,
    d::Float64,
    t_cut::Float64,
    banked::Float64,
    t_now::Float64,
)::Float64
    d = clamp(d, 1e-6, 1.0 - 1e-6)
    if banked <= 0.0 || t_now <= 0.0
        return O * curve_factor(d, t_cut)
    end
    t_cut <= t_now && return banked
    t_pin = max(t_now, 1.0)
    t_cut <= t_pin && return banked
    return banked + banked * remaining_factor(d, t_pin, t_cut)
end

# Minimal Xoshiro + Box-Muller so the spike does not require Random overlays at link time
# when compiling the smallest possible module. Full kernel may use Random.Xoshiro once
# validated; this keeps the feasibility spike self-contained.
mutable struct RngState
    s0::UInt64
    s1::UInt64
    s2::UInt64
    s3::UInt64
    has_spare::Bool
    spare::Float64
end

function seed_rng(seed::UInt64)::RngState
    # SplitMix64 expansion of a single seed into four Xoshiro lanes
    function splitmix(x::UInt64)
        x += 0x9e3779b97f4a7c15
        z = x
        z = (z ⊻ (z >> 30)) * 0xbf58476d1ce4e5b9
        z = (z ⊻ (z >> 27)) * 0x94d049bb133111eb
        return z ⊻ (z >> 31), x
    end
    x = seed
    s0, x = splitmix(x)
    s1, x = splitmix(x)
    s2, x = splitmix(x)
    s3, x = splitmix(x)
    return RngState(s0, s1, s2, s3, false, 0.0)
end

@inline function rotl(x::UInt64, k::Int)::UInt64
    return (x << k) | (x >> (64 - k))
end

function next_u64!(rng::RngState)::UInt64
    result = rotl(rng.s1 * 5, 7) * 9
    t = rng.s1 << 17
    rng.s2 ⊻= rng.s0
    rng.s3 ⊻= rng.s1
    rng.s1 ⊻= rng.s2
    rng.s0 ⊻= rng.s3
    rng.s2 ⊻= t
    rng.s3 = rotl(rng.s3, 45)
    return result
end

function next_f64!(rng::RngState)::Float64
    # Uniform in (0, 1)
    return (next_u64!(rng) >> 11) * 0x1.0p-53 + 0x1.0p-53
end

function next_randn!(rng::RngState)::Float64
    if rng.has_spare
        rng.has_spare = false
        return rng.spare
    end
    # Box–Muller
    u1 = max(next_f64!(rng), 1e-16)
    u2 = next_f64!(rng)
    r = sqrt(-2.0 * log(u1))
    theta = 2.0 * π * u2
    rng.spare = r * cos(theta)
    rng.has_spare = true
    return r * sin(theta)
end

# --- Spike entry: proves randn, exp/log, sort of 33 scores, flat buffers ---

"""
Minimal feasibility kernel.

`inp` / `out` are flat Float64 vectors. Writes 33 sorted descending scores derived
from seeded randn + exp transforms, plus a checksum.
"""
function spike_kernel!(out::Vector{Float64}, inp::Vector{Float64})::Int32
    n = Int(inp[1])  # expect 33
    seed = UInt64(trunc(Int64, inp[2]))
    rng = seed_rng(seed)
    scores = Vector{Float64}(undef, n)
    for i in 1:n
        z = next_randn!(rng)
        scores[i] = exp(log(1.0e7) + 0.5 * z)  # log-normal-ish
    end
    sort!(scores; rev = true)
    out[1] = Float64(n)
    s = 0.0
    for i in 1:n
        out[i + 1] = scores[i]
        s += scores[i]
    end
    out[n + 2] = s
    return Int32(0)
end

# --- Production simulation (simplified quadrature-free conditional sampling) ---
# Full nested quadrature lives in SMW.inference; the WASM kernel samples from
# precomputed discrete posteriors OR uses analytic conditionals with fixed σ grid
# packed by the host. For the initial kernel we pack per-film η grids from the
# native precomputation into the input buffer (host-side quadrature), then the
# WASM side only does MC composition — keeping AOT surface small.
#
# Alternative path: run_simulation! does a lightweight per-film analytic update
# at a single σ (median prior) for preview speed; full nested quad can be packed.

function logO_posterior_k!(
    zs::Vector{Float64},
    nK::Int,
    σ::Float64,
    μ_logO::Float64,
    σ_logO::Float64,
)::NTuple{3,Float64}
    σ = max(σ, 1e-6)
    σ_logO = max(σ_logO, 1e-6)
    if nK == 0
        return (0.0, μ_logO, σ_logO)
    end
    τ2 = σ_logO * σ_logO
    σ2 = σ * σ
    sumz = 0.0
    for i in 1:nK
        sumz += zs[i]
    end
    prec = 1.0 / τ2 + Float64(nK) / σ2
    post_var = 1.0 / prec
    post_mean = post_var * (μ_logO / τ2 + sumz / σ2)
    post_std = sqrt(post_var)
    # Evidence (for completeness; unused when host supplies weights)
    Q = 0.0
    S = 0.0
    for i in 1:nK
        r = zs[i] - μ_logO
        Q += r * r
        S += r
    end
    logdet = Float64(nK) * log(σ2) + log1p(Float64(nK) * τ2 / σ2)
    quad = Q / σ2 - (τ2 / (σ2 * (σ2 + Float64(nK) * τ2))) * S * S
    logZ = -0.5 * (Float64(nK) * log(2π) + logdet + quad)
    return (logZ, post_mean, post_std)
end

"""
Run Monte Carlo season grosses into `out` from packed `inp`.

Simplified in-kernel path: fixed σ=0.15, Hermite-like 8-point η grid with
analytic logO conditional per node, then sample. Host may later replace with
fully precomputed weights; this proves the numeric surface AOT-compiles.
"""
function run_simulation!(out::Vector{Float64}, inp::Vector{Float64})::Int32
    schema = inp[1]
    schema == KERNEL_SCHEMA || return Int32(1)
    n_films = Int(inp[2])
    n_draws = Int(inp[3])
    seed = UInt64(trunc(Int64, inp[4]))
    (n_films > 0 && n_draws > 0) || return Int32(2)
    rng = seed_rng(seed)

    # η grid (8 nodes) — standard GH transformed for N(0,1), then scaled per film
    # Using fixed relative offsets for AOT simplicity
    gh_x = (
        -2.930637420257244,
        -1.981656756334386,
        -1.157193712446780,
        -0.381186990207322,
         0.381186990207322,
         1.157193712446780,
         1.981656756334386,
         2.930637420257244,
    )
    gh_w = (
        0.000199604344352,
        0.017077983007413,
        0.207802325814892,
        0.661147012558241,
        0.661147012558241,
        0.207802325814892,
        0.017077983007413,
        0.000199604344352,
    )
    inv_sqrt_pi = 1.0 / sqrt(π)
    σ_obs = 0.15

    # Parse film block
    base = 7
    film_stride = 11
    # First pass: locate interval block
    iv_base = base + n_films * film_stride
    cursor = iv_base
    for f in 1:n_films
        off = base + (f - 1) * film_stride
        n_iv = Int(inp[off + 10])
        cursor += n_iv * 4
    end

    zs_buf = Vector{Float64}(undef, 64)
    out[1] = 0.0
    out[2] = Float64(n_films)
    out[3] = Float64(n_draws)
    out[4] = 0.0

    for draw in 1:n_draws
        iv_cursor = iv_base
        for f in 1:n_films
            off = base + (f - 1) * film_stride
            μ_logO = inp[off + 1]
            σ_logO = inp[off + 2]
            μ_η = inp[off + 3]
            σ_η = inp[off + 4]
            t_cut = inp[off + 5]
            banked = inp[off + 6]
            t_now = inp[off + 7]
            released = inp[off + 9] > 0.5
            n_iv = Int(inp[off + 10])

            # Collect z's for this film's intervals at each η — sample η first then condition
            # Build discrete posterior over η
            logw = Vector{Float64}(undef, 8)
            μO = Vector{Float64}(undef, 8)
            σO = Vector{Float64}(undef, 8)
            maxlw = -1.0e300
            for k in 1:8
                η = μ_η + sqrt(2.0) * σ_η * gh_x[k]
                d = clamp(logistic(η), 1e-6, 1.0 - 1e-6)
                nK = 0
                if released && n_iv > 0
                    for j in 1:n_iv
                        t0 = inp[iv_cursor + (j - 1) * 4 + 0]
                        t1 = inp[iv_cursor + (j - 1) * 4 + 1]
                        Δ = inp[iv_cursor + (j - 1) * 4 + 2]
                        fac = interval_factor(d, t0, t1)
                        if fac > 0.0 && Δ > 0.0
                            nK += 1
                            zs_buf[nK] = log(Δ) - log(fac)
                        end
                    end
                end
                logZ, m, s = logO_posterior_k!(zs_buf, nK, σ_obs, μ_logO, σ_logO)
                lw = log(gh_w[k] * inv_sqrt_pi) + logZ
                logw[k] = lw
                μO[k] = m
                σO[k] = s
                if lw > maxlw
                    maxlw = lw
                end
            end
            # Normalize and sample
            sumw = 0.0
            for k in 1:8
                logw[k] = exp(logw[k] - maxlw)
                sumw += logw[k]
            end
            u = next_f64!(rng) * sumw
            c = 0.0
            pick = 8
            for k in 1:8
                c += logw[k]
                if u <= c
                    pick = k
                    break
                end
            end
            η = μ_η + sqrt(2.0) * σ_η * gh_x[pick]
            d = clamp(logistic(η), 1e-6, 1.0 - 1e-6)
            logO = μO[pick] + σO[pick] * next_randn!(rng)
            O = exp(logO)
            g = season_total_k(O, d, t_cut, banked, t_now)
            if banked > 0.0 && g < banked
                g = banked
            end
            out[4 + (f - 1) + n_films * (draw - 1) + 1] = g
            iv_cursor += n_iv * 4
        end
    end
    return Int32(0)
end

end # module
