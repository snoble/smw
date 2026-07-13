"""
Closed-form cumulative domestic gross under geometric weekly decay.

Opening-week gross `O`, weekly retention `d ∈ (0,1)`. At fractional run-week `t`:

    cumulative(t) = O * (1 - d^t) / (1 - d)   for d ≠ 1
                  = O * t                     for d → 1
"""
function cumulative_gross(O::Real, d::Real, t::Real)
    O = float(O)
    d = float(d)
    t = float(t)
    t <= 0 && return 0.0
    if abs(d - 1.0) < 1e-12
        return O * t
    end
    return O * (1 - d^t) / (1 - d)
end

"""
Empirical Bayes hyperparameters from historical weekly trajectories.

Returns Dict type => (μ_logO, σ_logO, μ_logit_d, σ_logit_d), plus `"__pooled__"`.
"""
function fit_type_priors(historical::DataFrame)
    film_stats = NamedTuple[]
    for g in groupby(historical, [:year, :title, :type])
        g2 = sort(DataFrame(g), :week)
        O = Float64(g2.cumulative_gross[1])
        F = Float64(g2.final_gross[1])
        d = clamp(1 - O / max(F, O * 1.01), 0.05, 0.95)
        push!(
            film_stats,
            (
                type = String(g2.type[1]),
                logO = log(max(O, 1.0)),
                logit_d = log(d / (1 - d)),
            ),
        )
    end

    pooled_logO = mean(s.logO for s in film_stats)
    pooled_logit_d = mean(s.logit_d for s in film_stats)
    pooled_σ_logO = max(std([s.logO for s in film_stats]; corrected = false), 0.5)
    pooled_σ_logit_d = max(std([s.logit_d for s in film_stats]; corrected = false), 0.3)

    by_type = Dict{String,NamedTuple}()
    for t in unique(s.type for s in film_stats)
        subset = filter(s -> s.type == t, film_stats)
        if length(subset) < 2
            by_type[t] = (
                μ_logO = pooled_logO,
                σ_logO = pooled_σ_logO,
                μ_logit_d = pooled_logit_d,
                σ_logit_d = pooled_σ_logit_d,
            )
        else
            by_type[t] = (
                μ_logO = mean(s.logO for s in subset),
                σ_logO = max(std([s.logO for s in subset]; corrected = false), 0.3),
                μ_logit_d = mean(s.logit_d for s in subset),
                σ_logit_d = max(std([s.logit_d for s in subset]; corrected = false), 0.2),
            )
        end
    end
    by_type["__pooled__"] = (
        μ_logO = pooled_logO,
        σ_logO = pooled_σ_logO,
        μ_logit_d = pooled_logit_d,
        σ_logit_d = pooled_σ_logit_d,
    )
    return by_type
end

prior_for(type::AbstractString, priors::AbstractDict) =
    get(priors, String(type), priors["__pooled__"])

# Default priors for unreleased films (used when history is synthetic / thin).
# Prefer per-film `opening_prior_m` in films_2026.csv; these are type fallbacks only.
const UNRELEASED_OPENING_PRIORS = Dict{String,Float64}(
    "animation" => 28_000_000.0,
    "superhero" => 90_000_000.0,
    "franchise" => 32_000_000.0,
    "horror" => 16_000_000.0,
    "comedy" => 10_000_000.0,
    "drama" => 9_000_000.0,
)

# Typical weekly retention by type (higher = longer legs). Used for unreleased films
# so decay isn't identical across the whole slate when EB history collapses to pooled.
const UNRELEASED_DECAY_D = Dict{String,Float64}(
    "animation" => 0.58,
    "superhero" => 0.48,
    "franchise" => 0.50,
    "horror" => 0.32,
    "comedy" => 0.38,
    "drama" => 0.45,
)

const UNRELEASED_LOGO_STD = 0.55          # ~1.7× up/down at 1σ — spreads the field
const UNRELEASED_LOGO_STD_CURATED = 0.40  # tighter when CSV sets opening_prior_m
const UNRELEASED_LOGIT_D_STD = 0.35

logit(p) = log(p / (1 - p))

"""Opening + decay prior for one unreleased film (before notebook overrides)."""
function unreleased_prior(film::Film)
    if !ismissing(film.opening_prior_m) && film.opening_prior_m > 0
        O = Float64(film.opening_prior_m) * 1_000_000
        σO = UNRELEASED_LOGO_STD_CURATED
    else
        O = get(UNRELEASED_OPENING_PRIORS, film.type, 12_000_000.0)
        σO = UNRELEASED_LOGO_STD
    end
    d = clamp(get(UNRELEASED_DECAY_D, film.type, 0.42), 0.05, 0.95)
    return (
        μ_logO = log(O),
        σ_logO = σO,
        μ_logit_d = logit(d),
        σ_logit_d = UNRELEASED_LOGIT_D_STD,
    )
end

"""Max observed cumulative gross per film (dollars already banked)."""
function observed_floors(season::SeasonData)
    floors = Dict{String,Float64}()
    for f in season.films
        floors[f.title] = max(0.0, f.cumulative_gross)
    end
    for o in season.observations
        floors[o.film] = max(get(floors, o.film, 0.0), o.cumulative_gross)
    end
    return floors
end

"""Observation time (fractional run-weeks) of the latest cumulative for each film."""
function observed_times(season::SeasonData)
    times = Dict{String,Float64}()
    for f in season.films
        if f.released && f.cumulative_gross > 0
            times[f.title] = run_weeks(f.release_date, f.as_of)
        end
    end
    for o in season.observations
        o.cumulative_gross > 0 || continue
        prev = get(times, o.film, -Inf)
        if o.t >= prev
            times[o.film] = o.t
        end
    end
    return times
end

"""
Season total as banked + positive remaining.

For a released film with banked gross `C` at run-week `t_now`, pin the geometric
curve to that observation and project remaining to Labor Day:

    G = C * (1 - d^{t_cut}) / (1 - d^{t_pin})     with t_pin = max(t_now, 1)

`t_pin` floors at one week: pinning at `t ≪ 1` (mid-opening-weekend) makes
`(1 - d^{t_cut}) / (1 - d^{t_now})` explode — e.g. a weak \$43M after three days
extrapolating to ~\$250M. Treating early banked as ≥ end-of-opening-week keeps
remaining proportional to a real opening, not a singular sub-week ratio.

For an unreleased film (`C == 0`), fall back to the usual opening curve
`cumulative(O, d, t_cut)`.
"""
function season_total(
    O::Real,
    d::Real,
    t_cut::Real;
    banked::Real = 0.0,
    t_now::Real = 0.0,
)
    d = clamp(float(d), 1e-6, 1 - 1e-6)
    t_cut = float(t_cut)
    banked = float(banked)
    t_now = float(t_now)
    if banked <= 0 || t_now <= 0
        return cumulative_gross(O, d, t_cut)
    end
    # Remaining must be non-negative: if t_cut <= t_now, season is over for this film.
    t_cut <= t_now && return banked
    # Floor pin time at 1 week so mid-opening-weekend banked doesn't 5–6× extrapolate.
    t_pin = max(t_now, 1.0)
    t_cut <= t_pin && return banked
    # d ∈ (0,1) and t_pin ≥ 1 ⇒ denom ∈ (0,1); remaining ≥ 0 when t_cut > t_pin.
    future = banked * (d^t_pin - d^t_cut) / (1 - d^t_pin)
    return banked + future
end

@model function RunCurveModelArrays(
    n::Int,
    μ_logO::Vector{Float64},
    σ_logO::Vector{Float64},
    μ_logit_d::Vector{Float64},
    σ_logit_d::Vector{Float64},
    t_cutoffs::Vector{Float64},
    obs_film_idx::Vector{Int},
    obs_t::Vector{Float64},
    obs_log_gross::Vector{Float64},
    override_idx::Vector{Int},
    override_logG::Vector{Float64},
    override_σ::Vector{Float64},
)
    σ_obs ~ truncated(Normal(0.15, 0.1), 0.02, 1.0)

    logO ~ arraydist([Normal(μ_logO[i], σ_logO[i]) for i in 1:n])
    logit_d ~ arraydist([Normal(μ_logit_d[i], σ_logit_d[i]) for i in 1:n])

    O = exp.(logO)
    d = 1 ./ (1 .+ exp.(-logit_d))

    for k in eachindex(obs_film_idx)
        i = obs_film_idx[k]
        μ = log(max(cumulative_gross(O[i], d[i], obs_t[k]), 1.0))
        obs_log_gross[k] ~ Normal(μ, σ_obs)
    end

    # Soft G overrides: observe a dummy equal to the prior mean so the likelihood
    # pulls log(G) toward override_logG (Turing requires a plain LHS on ~).
    for j in eachindex(override_idx)
        i = override_idx[j]
        G = cumulative_gross(O[i], d[i], t_cutoffs[i])
        override_logG[j] ~ Normal(log(max(G, 1.0)), override_σ[j])
    end # COV_EXCL_LINE — Turing @model expands this `end` as never-hit
end

function build_array_model(season::SeasonData; overrides::Dict = Dict{String,NamedTuple}())
    films = season.films
    n = length(films)
    titles = [f.title for f in films]
    types = [f.type for f in films]
    tcuts = Float64[t_cutoff(f.release_date) for f in films]
    priors = fit_type_priors(season.historical)

    μ_logO = Float64[]
    σ_logO = Float64[]
    μ_logit_d = Float64[]
    σ_logit_d = Float64[]
    for i in 1:n
        p = prior_for(types[i], priors)
        μO, σO = p.μ_logO, p.σ_logO
        μd, σd = p.μ_logit_d, p.σ_logit_d
        film = films[i]
        # Unreleased: curated opening_prior_m (or type fallback) + type-specific decay.
        # Avoids the synthetic-history tentpole prior and same-type median clustering.
        if !film.released && !haskey(overrides, titles[i])
            up = unreleased_prior(film)
            μO, σO = up.μ_logO, up.σ_logO
            μd, σd = up.μ_logit_d, up.σ_logit_d
        elseif !film.released && haskey(overrides, titles[i])
            # Keep type decay even when opening is overridden (e.g. Spidey slider).
            up = unreleased_prior(film)
            μd, σd = up.μ_logit_d, up.σ_logit_d
        end
        if haskey(overrides, titles[i])
            ov = overrides[titles[i]]
            if hasproperty(ov, :logO_mean)
                μO = Float64(ov.logO_mean)
                σO = hasproperty(ov, :logO_std) ? Float64(ov.logO_std) : 0.25
            end
        end
        push!(μ_logO, μO)
        push!(σ_logO, σO)
        push!(μ_logit_d, μd)
        push!(σ_logit_d, σd)
    end

    title_idx = Dict(t => i for (i, t) in enumerate(titles))
    obs_idx = Int[]
    obs_t = Float64[]
    obs_log = Float64[]
    for o in season.observations
        o.cumulative_gross > 0 || continue
        o.t > 0 || continue
        push!(obs_idx, title_idx[o.film])
        push!(obs_t, o.t)
        push!(obs_log, log(o.cumulative_gross))
    end

    override_idx = Int[]
    override_logG = Float64[]
    override_σ = Float64[]
    for (title, ov) in overrides
        hasproperty(ov, :G_mean) || continue
        push!(override_idx, title_idx[title])
        push!(override_logG, log(Float64(ov.G_mean)))
        σG = hasproperty(ov, :G_std) ? Float64(ov.G_std) : Float64(ov.G_mean) * 0.25
        push!(override_σ, σG / Float64(ov.G_mean))
    end

    model = RunCurveModelArrays(
        n,
        μ_logO,
        σ_logO,
        μ_logit_d,
        σ_logit_d,
        tcuts,
        obs_idx,
        obs_t,
        obs_log,
        override_idx,
        override_logG,
        override_σ,
    )
    return (; model, titles, tcuts, types, n)
end

"""Sample posterior with NUTS. Returns `(chain, titles, tcuts, types, n)`."""
function sample_posterior(
    season::SeasonData;
    overrides::Dict = Dict{String,NamedTuple}(),
    n_samples::Int = 400,
    seed::Int = 42,
    progress::Bool = false,
)
    inputs = build_array_model(season; overrides)
    Random.seed!(seed)
    chain = sample(inputs.model, NUTS(0.65), n_samples; progress)
    return (; chain, titles = inputs.titles, tcuts = inputs.tcuts, types = inputs.types, n = inputs.n)
end

"""Extract season-cutoff gross matrix `G` (films × draws).

Season total = **banked + positive remaining**, where remaining is the geometric
curve's growth from the latest observation time to Labor Day, pinned so the
curve matches the banked gross at `t_now`. Unreleased films use the opening
curve from zero.
"""
function season_gross_draws(
    result::NamedTuple;
    floors::Union{Nothing,AbstractDict{<:AbstractString,<:Real}} = nothing,
    times::Union{Nothing,AbstractDict{<:AbstractString,<:Real}} = nothing,
)
    chain = result.chain
    n = result.n
    tcuts = result.tcuts
    titles = result.titles
    df = DataFrame(chain)
    banked = if floors === nothing
        zeros(n)
    else
        [Float64(get(floors, titles[i], 0.0)) for i in 1:n]
    end
    t_now = if times === nothing
        zeros(n)
    else
        [Float64(get(times, titles[i], 0.0)) for i in 1:n]
    end
    G = Matrix{Float64}(undef, n, nrow(df))
    for draw in 1:nrow(df)
        for i in 1:n
            logO = df[draw, Symbol("logO[$i]")]
            logit_d = df[draw, Symbol("logit_d[$i]")]
            O = exp(logO)
            d = 1 / (1 + exp(-logit_d))
            G[i, draw] = season_total(O, d, tcuts[i]; banked = banked[i], t_now = t_now[i])
        end
    end
    return G
end

"""Prior-predictive season grosses (no observations) for sanity checks."""
function prior_predictive_grosses(season::SeasonData; n_draws::Int = 200, seed::Int = 1)
    Random.seed!(seed)
    films = season.films
    priors = fit_type_priors(season.historical)
    n = length(films)
    G = Matrix{Float64}(undef, n, n_draws)
    for draw in 1:n_draws, i in 1:n
        film = films[i]
        if !film.released
            up = unreleased_prior(film)
            μO, σO = up.μ_logO, up.σ_logO
            μd, σd = up.μ_logit_d, up.σ_logit_d
        else
            p = prior_for(film.type, priors)
            μO, σO = p.μ_logO, p.σ_logO
            μd, σd = p.μ_logit_d, p.σ_logit_d
        end
        logO = rand(Normal(μO, σO))
        logit_d = rand(Normal(μd, σd))
        O = exp(logO)
        d = 1 / (1 + exp(-logit_d))
        G[i, draw] = cumulative_gross(O, d, t_cutoff(film.release_date))
    end
    return G
end
