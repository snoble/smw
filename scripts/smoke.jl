#!/usr/bin/env julia
# End-to-end smoke: load data → short posterior → simulate → print summary.
#   nix-shell --run 'julia --project scripts/smoke.jl'

using SMW
using Statistics

data_dir = joinpath(@__DIR__, "..", "data")
season = load_season(data_dir)

println("Films: ", length(season.films))
println("Observations: ", length(season.observations))
println("Players: ", join(keys(season.picks), ", "))

overrides = Dict{String,NamedTuple}(
    "Spider-Man: Brand New Day" => (logO_mean = log(150_000_000), logO_std = 0.4),
    "The Odyssey" => (logO_mean = log(80_000_000), logO_std = 0.5),
)

println("Sampling posterior (small draw count)…")
posterior = sample_posterior(season; overrides, n_samples = 150, progress = true)
println("Simulating outcomes…")
sim = simulate_outcomes(season, posterior)

println("\nTop-10 probabilities (P > 5%):")
for i in sortperm(sim.top10_prob; rev = true)
    sim.top10_prob[i] < 0.05 && break
    println("  ", rpad(sim.titles[i], 40), " ", round(100 * sim.top10_prob[i]; digits = 1), "%")
end

println("\nWin probability (sole first):")
for (p, w) in zip(sim.players, sim.win_sole)
    println("  ", rpad(p, 12), " ", round(100 * w; digits = 1), "%")
end

println("\nWin probability (sole or tied first):")
for (p, w) in zip(sim.players, sim.win_shared)
    println("  ", rpad(p, 12), " ", round(100 * w; digits = 1), "%")
end

mkpath(joinpath(@__DIR__, "..", "output"))
println("\nSmoke OK.")
