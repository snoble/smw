#!/usr/bin/env julia
# Audit the 2026 candidate field against release dates and weekly theaters.
#   nix-shell --run 'julia --project scripts/audit_candidate_field.jl'

using SMW
using Dates

data_dir = joinpath(@__DIR__, "..", "data")
season = load_season(data_dir)

println("Film count: ", length(season.films))

released = filter(f -> f.released, season.films)
unreleased = filter(f -> !f.released, season.films)

println("\nReleased (", length(released), "):")
for f in sort(released; by = x -> x.release_date)
    println("  ", rpad(f.title, 45), " ", f.release_date, "  \$", Int(round(f.cumulative_gross)))
end

println("\nUnreleased (", length(unreleased), "):")
for f in sort(unreleased; by = x -> x.release_date)
    println("  ", rpad(f.title, 45), " ", f.release_date)
end

println("\nFlags: t_now inconsistent with release_date (released but t_now==0, or unreleased with banked gross):")
flags = String[]
for f in season.films
    t_now = run_weeks(f.release_date, f.as_of)
    if f.released && f.cumulative_gross > 0 && t_now <= 0
        push!(flags, "RELEASED_BUT_TNOW_ZERO: $(f.title) release=$(f.release_date) as_of=$(f.as_of)")
    end
    if !f.released && f.cumulative_gross > 0
        push!(flags, "UNRELEASED_WITH_GROSS: $(f.title) gross=$(f.cumulative_gross)")
    end
    if f.released && f.release_date > f.as_of
        push!(flags, "RELEASE_AFTER_AS_OF: $(f.title) release=$(f.release_date) as_of=$(f.as_of)")
    end
end
if isempty(flags)
    println("  (none)")
else
    for msg in flags
        println("  ", msg)
    end
end

sheep = only(f for f in season.films if f.title == "The Sheep Detectives")
@assert sheep.release_date == Date(2026, 5, 8) "Sheep Detectives release_date must be 2026-05-08; got $(sheep.release_date)"

sheep_obs = filter(o -> o.film == "The Sheep Detectives", season.observations)
@assert !isempty(sheep_obs) "Sheep Detectives must have weekly observations"
latest = argmax(o -> (o.date, o.t), sheep_obs)
@assert !ismissing(latest.theaters) "Sheep Detectives latest obs must have theaters"
@assert latest.theaters <= 200 "Sheep Detectives latest theaters must be <= 200; got $(latest.theaters)"

println("\nAssertions OK:")
println("  The Sheep Detectives release_date = ", sheep.release_date)
println("  Latest theaters = ", latest.theaters, " (source=", latest.source, ")")
println("Audit complete.")
