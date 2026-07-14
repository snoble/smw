#!/usr/bin/env julia
# Export the versioned INPUT bundle for the browser inference worker.
#
# Fitted type priors + raw 2026 observations/metadata/picks — no posterior draws.
#
#   nix-shell --run 'julia --project scripts/export_viewer_data.jl'

using Dates
using SMW

const ROOT = normpath(joinpath(@__DIR__, ".."))
const OUT_JSON = joinpath(ROOT, "site", "smw2026_data.json")

const SCHEMA_VERSION = 2
const MODEL_VERSION = "factored-gh-gl-v1"
const KERNEL_VERSION = 1
const PRIOR_VERSION = "eb-synthetic-v1-provisional"
const DEFAULT_SEED = 20260713
const DEFAULT_ETA_ORDER = 16
const DEFAULT_SIGMA_ORDER = 16

const CONTROLLED = Dict(
    "Spider-Man: Brand New Day" => (
        key = "spidey",
        label = "Spider-Man: Brand New Day",
        min = 50,
        max = 250,
        step = 10,
        default = 180,
        sigma = 0.20,
        hint = "Deadline tracking \$180–190M (Jul 2026); Boxoffice Pro long-range \$230–250M",
    ),
    "The Odyssey" => (
        key = "odyssey",
        label = "The Odyssey",
        min = 30,
        max = 150,
        step = 5,
        default = 105,
        sigma = 0.35,
        hint = "Boxoffice Pro / BOT ~\$100–120M; earlier Deadline range \$80–100M",
    ),
    "PAW Patrol: The Dino Movie" => (
        key = "paw",
        label = "PAW Patrol: The Dino Movie",
        min = 10,
        max = 80,
        step = 5,
        default = 40,
        sigma = 0.35,
        hint = "Type/curated prior — no firm public tracking yet",
    ),
    "Mutiny" => (
        key = "mutiny",
        label = "Mutiny",
        min = 10,
        max = 90,
        step = 5,
        default = 45,
        sigma = 0.35,
        hint = "Type/curated prior — no firm public tracking yet",
    ),
    "Insidious: Out of the Further" => (
        key = "insidious",
        label = "Insidious: Out of the Further",
        min = 5,
        max = 60,
        step = 5,
        default = 30,
        sigma = 0.35,
        hint = "Type/curated prior — no firm public tracking yet",
    ),
)

json_escape(s::AbstractString) = replace(
    replace(replace(replace(replace(s, '\\' => "\\\\"), '"' => "\\\""), '\n' => "\\n"), '\r' => "\\r"),
    '\t' => "\\t",
)
q(s) = "\"" * json_escape(String(s)) * "\""
jnum(x) = isfinite(Float64(x)) ? string(round(Float64(x); sigdigits = 8)) : "0"
jmaybe(x) = x === nothing || x isa Missing ? "null" : jnum(x)

function write_vec(io, xs; strings = false)
    print(io, "[")
    for (i, x) in enumerate(xs)
        i > 1 && print(io, ",")
        print(io, strings ? q(x) : jnum(x))
    end
    print(io, "]")
end

println("Loading season + fitting type priors…")
season = load_season(joinpath(ROOT, "data"))
type_priors = fit_type_priors(season.historical)
film_priors = film_priors_from_season(season, type_priors)
floors = observed_floors(season)
times = observed_times(season)
intervals = interval_observations(season.observations)
title_idx = Dict(f.title => i for (i, f) in enumerate(season.films))

# Apply control σ overrides on unreleased controlled films (μ comes from slider at runtime)
for (i, film) in enumerate(season.films)
    control = get(CONTROLLED, film.title, nothing)
    control === nothing && continue
    pr = film_priors[i]
    film_priors[i] = FilmPrior(
        pr.title,
        pr.μ_logO,
        Float64(control.sigma),
        pr.μ_logit_d,
        pr.σ_logit_d,
        pr.t_cut,
        pr.banked,
        pr.t_now,
        pr.theaters,
        pr.released,
    )
end

mkpath(dirname(OUT_JSON))
open(OUT_JSON, "w") do io
    print(io, "{")
    print(io, "\"schema_version\":", SCHEMA_VERSION)
    print(io, ",\"model_version\":", q(MODEL_VERSION))
    print(io, ",\"kernel_version\":", KERNEL_VERSION)
    print(io, ",\"prior_version\":", q(PRIOR_VERSION))
    print(io, ",\"seeds\":{\"default\":", DEFAULT_SEED, "}")
    print(io, ",\"quadrature\":{\"eta\":", DEFAULT_ETA_ORDER, ",\"sigma\":", DEFAULT_SIGMA_ORDER, "}")

    print(io, ",\"type_priors\":{")
    types = sort(collect(keys(type_priors)))
    for (i, t) in enumerate(types)
        i > 1 && print(io, ",")
        p = type_priors[t]
        print(
            io,
            q(t), ":{",
            "\"mu_logO\":", jnum(p.μ_logO),
            ",\"sigma_logO\":", jnum(p.σ_logO),
            ",\"mu_logit_d\":", jnum(p.μ_logit_d),
            ",\"sigma_logit_d\":", jnum(p.σ_logit_d),
            "}",
        )
    end
    print(io, "}")

    print(io, ",\"films\":[")
    for (i, film) in enumerate(season.films)
        i > 1 && print(io, ",")
        pr = film_priors[i]
        control = get(CONTROLLED, film.title, nothing)
        opening = film.opening_prior_m
        theaters = pr.theaters isa Missing ? nothing : Int(pr.theaters)
        print(
            io,
            "{\"title\":", q(film.title),
            ",\"type\":", q(film.type),
            ",\"release_date\":", q(Dates.format(film.release_date, dateformat"yyyy-mm-dd")),
            ",\"released\":", film.released ? "true" : "false",
            ",\"banked\":", jnum(get(floors, film.title, 0.0)),
            ",\"t_now\":", jnum(get(times, film.title, 0.0)),
            ",\"t_cut\":", jnum(t_cutoff(film.release_date)),
            ",\"theaters\":", jmaybe(theaters),
            ",\"opening_prior_m\":", opening isa Missing ? "null" : jnum(opening),
            ",\"mu_logO\":", jnum(pr.μ_logO),
            ",\"sigma_logO\":", jnum(pr.σ_logO),
            ",\"mu_logit_d\":", jnum(pr.μ_logit_d),
            ",\"sigma_logit_d\":", jnum(pr.σ_logit_d),
            ",\"controlled\":", control === nothing ? "null" : q(control.key),
            "}",
        )
    end
    print(io, "]")

    print(io, ",\"intervals\":[")
    for (i, iv) in enumerate(intervals)
        i > 1 && print(io, ",")
        th = iv.theaters_end isa Missing ? nothing : Int(iv.theaters_end)
        print(
            io,
            "{\"film\":", q(iv.film),
            ",\"t_start\":", jnum(iv.t_start),
            ",\"t_end\":", jnum(iv.t_end),
            ",\"interval_gross\":", jnum(iv.interval_gross),
            ",\"theaters_end\":", jmaybe(th),
            "}",
        )
    end
    print(io, "]")

    print(io, ",\"controls\":[")
    controls = sort(collect(values(CONTROLLED)); by = c -> findfirst(==(c.key), ["spidey", "odyssey", "paw", "mutiny", "insidious"]))
    for (i, c) in enumerate(controls)
        i > 1 && print(io, ",")
        print(
            io,
            "{\"key\":", q(c.key),
            ",\"label\":", q(c.label),
            ",\"min\":", c.min,
            ",\"max\":", c.max,
            ",\"step\":", c.step,
            ",\"default\":", c.default,
            ",\"sigma\":", jnum(c.sigma),
            ",\"hint\":", q(c.hint),
            "}",
        )
    end
    print(io, "]")

    print(io, ",\"players\":[")
    players = sort(collect(keys(season.picks)))
    for (i, player) in enumerate(players)
        i > 1 && print(io, ",")
        picks = season.picks[player]
        ranked = [title_idx[t] - 1 for (_, t) in sort(picks.ranked; by = first)]
        dark = [title_idx[t] - 1 for t in picks.dark_horses]
        print(io, "{\"name\":", q(player), ",\"ranked\":")
        write_vec(io, ranked)
        print(io, ",\"dark_horses\":")
        write_vec(io, dark)
        print(io, "}")
    end
    print(io, "]")
    print(io, "}")
end

n_released = count(f -> f.released, season.films)
println("Wrote $OUT_JSON")
println("  schema=$SCHEMA_VERSION model=$MODEL_VERSION kernel=$KERNEL_VERSION prior=$PRIOR_VERSION")
println("  films: $(length(season.films)) ($n_released released)")
println("  intervals: $(length(intervals))")
println("  type priors: $(length(type_priors))")
println("  bytes: $(filesize(OUT_JSON))")
