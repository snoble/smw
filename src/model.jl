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
    end
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
        if haskey(overrides, titles[i])
            ov = overrides[titles[i]]
            if hasproperty(ov, :logO_mean)
                μO = Float64(ov.logO_mean)
                σO = hasproperty(ov, :logO_std) ? Float64(ov.logO_std) : 0.3
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

"""Extract season-cutoff gross matrix `G` (films × draws) from a posterior result."""
function season_gross_draws(result::NamedTuple)
    chain = result.chain
    n = result.n
    tcuts = result.tcuts
    df = DataFrame(chain)
    G = Matrix{Float64}(undef, n, nrow(df))
    for draw in 1:nrow(df)
        for i in 1:n
            logO = df[draw, Symbol("logO[$i]")]
            logit_d = df[draw, Symbol("logit_d[$i]")]
            O = exp(logO)
            d = 1 / (1 + exp(-logit_d))
            G[i, draw] = cumulative_gross(O, d, tcuts[i])
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
        p = prior_for(films[i].type, priors)
        logO = rand(Normal(p.μ_logO, p.σ_logO))
        logit_d = rand(Normal(p.μ_logit_d, p.σ_logit_d))
        O = exp(logO)
        d = 1 / (1 + exp(-logit_d))
        G[i, draw] = cumulative_gross(O, d, t_cutoff(films[i].release_date))
    end
    return G
end
