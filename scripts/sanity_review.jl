#!/usr/bin/env julia
# Full-field sanity pass for analysis + data consistency.
#   nix-shell --run 'julia --project scripts/sanity_review.jl'

using SMW
using Statistics
using Dates
using DataFrames

data_dir = joinpath(@__DIR__, "..", "data")
season = load_season(data_dir)

println("=== DATA SANITY ===")
println("films=", length(season.films), " obs=", length(season.observations), " players=", length(season.picks))

for (p, pk) in sort(collect(season.picks); by = first)
    ranks = first.(pk.ranked)
    println("  $p: ranked=$(length(pk.ranked)) ranks=$ranks dark=$(length(pk.dark_horses))")
    @assert sort(ranks) == collect(1:10)
    @assert length(pk.dark_horses) == 3
end

titles = [f.title for f in season.films]
@assert length(titles) == length(unique(titles))

for f in season.films
    if f.released && f.cumulative_gross == 0
        println("WARN released with registry gross 0: ", f.title, " — ", f.notes)
    end
end

floors = observed_floors(season)
times = observed_times(season)
for f in season.films
    if f.released && f.cumulative_gross > 0
        fl = floors[f.title]
        if abs(fl - f.cumulative_gross) / max(fl, 1) > 0.01
            println(
                "WARN floor!=film registry: ",
                f.title,
                " film=",
                round(Int, f.cumulative_gross / 1e6),
                "M floor=",
                round(Int, fl / 1e6),
                "M",
            )
        end
    elseif f.released && f.cumulative_gross == 0 && get(floors, f.title, 0.0) > 0
        println(
            "WARN registry 0 but weekly floor>0: ",
            f.title,
            " floor=",
            round(Int, floors[f.title] / 1e6),
            "M",
        )
    end
end

println(
    "historical rows=",
    nrow(season.historical),
    " years=",
    sort(unique(season.historical.year)),
)
println("historical types=", sort(unique(String.(season.historical.type))))

overrides = Dict{String,NamedTuple}(
    "Spider-Man: Brand New Day" => (logO_mean = log(180e6), logO_std = 0.2),
    "The Odyssey" => (logO_mean = log(80e6), logO_std = 0.35),
)
println("\n=== POSTERIOR (n=300, Spidey=180) ===")
post = sample_posterior(season; overrides, n_samples = 300, progress = true)
G = season_gross_draws(post; floors, times)
sim = simulate_outcomes(post.titles, G, season.picks)

viol = 0
mult = Float64[]
for (i, t) in enumerate(sim.titles)
    C = get(floors, t, 0.0)
    for j in 1:size(G, 2)
        if G[i, j] + 1e-6 < C
            viol += 1
        end
    end
    if C > 0
        push!(mult, median(G[i, :]) / C)
    end
end
println("banked>G violations: ", viol)
println(
    "median G/banked multipliers (released): min=",
    round(minimum(mult); digits = 2),
    " med=",
    round(median(mult); digits = 2),
    " max=",
    round(maximum(mult); digits = 2),
)

println("\nHigh remaining (median G/banked > 2):")
for (i, t) in enumerate(sim.titles)
    C = get(floors, t, 0.0)
    C <= 0 && continue
    m = median(G[i, :]) / C
    m > 2 || continue
    film = season.films[findfirst(f -> f.title == t, season.films)]
    tw = get(times, t, NaN)
    println(
        "  ",
        rpad(t, 40),
        " banked=",
        lpad(string(round(Int, C / 1e6)) * "M", 5),
        " med=",
        lpad(string(round(Int, median(G[i, :]) / 1e6)) * "M", 5),
        " x",
        round(m; digits = 2),
        " t_now=",
        round(tw; digits = 1),
        " t_cut=",
        round(t_cutoff(film.release_date); digits = 1),
    )
end

println("\n=== FULL FIELD by median season G ===")
med = [median(G[i, :]) for i in 1:length(sim.titles)]
ord = sortperm(med; rev = true)
for (rank, i) in enumerate(ord)
    C = get(floors, sim.titles[i], 0.0)
    println(
        lpad(string(rank), 2),
        ". ",
        rpad(sim.titles[i], 40),
        " banked=",
        lpad(C > 0 ? string(round(Int, C / 1e6)) * "M" : "—", 5),
        " med=",
        lpad(string(round(Int, med[i] / 1e6)) * "M", 5),
        " [",
        round(Int, quantile(G[i, :], 0.05) / 1e6),
        "-",
        round(Int, quantile(G[i, :], 0.95) / 1e6),
        "]",
        " Top10=",
        lpad(string(round(100 * sim.top10_prob[i]; digits = 1)) * "%", 6),
        " #1=",
        lpad(string(round(100 * sim.rank_prob[i, 1]; digits = 1)) * "%", 5),
    )
end

println("\n=== PLAYER OUTCOMES ===")
for i in sortperm(sim.win_shared; rev = true)
    println(
        rpad(sim.players[i], 10),
        " sole=",
        round(100 * sim.win_sole[i]; digits = 1),
        "%",
        " tied=",
        round(100 * sim.win_shared[i]; digits = 1),
        "%",
        " avg=",
        round(mean(sim.scores[i, :]); digits = 1),
        " p10=",
        round(quantile(sim.scores[i, :], 0.1); digits = 1),
        " p50=",
        round(quantile(sim.scores[i, :], 0.5); digits = 1),
        " p90=",
        round(quantile(sim.scores[i, :], 0.9); digits = 1),
    )
end
println(
    "sum sole=",
    round(sum(sim.win_sole); digits = 4),
    " sum shared=",
    round(sum(sim.win_shared); digits = 4),
)
n_lock = count(sim.top10_prob .> 0.5)
n_any = count(sim.top10_prob .> 0.05)
println("films with P(Top10)>50%: ", n_lock, "  >5%: ", n_any)
println("sum of Top10 probs (should ~10): ", round(sum(sim.top10_prob); digits = 2))

println("\n=== SPIDEY SENSITIVITY (tied win %) ===")
for open_m in [100, 150, 180, 220]
    ov = Dict{String,NamedTuple}(
        "Spider-Man: Brand New Day" => (logO_mean = log(open_m * 1e6), logO_std = 0.2),
        "The Odyssey" => (logO_mean = log(80e6), logO_std = 0.35),
    )
    p2 = sample_posterior(season; overrides = ov, n_samples = 200, progress = false)
    s2 = simulate_outcomes(season, p2)
    pi = findfirst(==("Peter"), s2.players)
    gi = findfirst(==("Germain"), s2.players)
    println(
        "  open=",
        open_m,
        "M  Peter tied=",
        round(100 * s2.win_shared[pi]; digits = 1),
        "%  Germain tied=",
        round(100 * s2.win_shared[gi]; digits = 1),
        "%",
    )
end

println("\nSANITY SCRIPT DONE")
