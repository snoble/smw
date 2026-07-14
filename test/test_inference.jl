@testset "analytic logO posterior conjugacy" begin
    # One perfect observation: interval = O * interval_factor → z = logO exactly
    d = 0.5
    O = 40_000_000.0
    t0, t1 = 0.0, 1.0
    Δ = O * interval_factor(d, t0, t1)
    iv = [(film = "X", t_start = t0, t_end = t1, interval_gross = Δ, theaters_end = 3000)]
    μ, τ = log(O), 1.0
    σ = 0.05
    logZ, m, s = logO_posterior(iv, d, σ, μ, τ)
    @test isfinite(logZ)
    @test abs(m - log(O)) < 0.02
    @test s < τ  # data shrinks posterior
end

@testset "interval_factor consistency with cumulative_gross" begin
    O, d = 10_000_000.0, 0.55
    for (t0, t1) in ((0.0, 1.0), (1.0, 2.0), (2.0, 5.0))
        Δ_curve = cumulative_gross(O, d, t1) - cumulative_gross(O, d, t0)
        Δ_fac = O * interval_factor(d, t0, t1)
        @test isapprox(Δ_curve, Δ_fac; rtol = 1e-10)
    end
end

@testset "Sheep Detectives near-terminal posterior is tight" begin
    season = load_season(DATA)
    priors = fit_type_priors(season.historical)
    film_priors = film_priors_from_season(season, priors)
    intervals = interval_observations(season.observations)
    sheep_i = findfirst(p -> p.title == "The Sheep Detectives", film_priors)
    @test sheep_i !== nothing
    sheep = film_priors[sheep_i]
    @test sheep.banked > 65e6
    @test sheep.theaters isa Int && sheep.theaters <= 200
    G, diag = sample_factored_grosses(film_priors, intervals, 2000; seed = 7)
    qs = quantile(G[sheep_i, :], [0.05, 0.5, 0.95])
    # Near-terminal: 90% interval should sit close to banked (~66M), not a wide-release 100M+ upside
    @test qs[1] >= sheep.banked * 0.98
    @test qs[3] <= sheep.banked * 1.15
    @test qs[3] - qs[1] < 8e6
end

@testset "rank_list_distance / representative win draw" begin
    titles = ["A", "B", "C", "D"]
    G = [
        100.0 90.0 80.0
        90.0 100.0 70.0
        80.0 70.0 100.0
        10.0 10.0 10.0
    ]
    # draw 1 top: A,B,C ; draw 2: B,A,C ; draw 3: C,A,B
    idx = representative_win_draw(titles, G, [1, 2, 3]; top_n = 3)
    @test idx in (1, 2, 3)
    @test rank_list_distance(["A", "B"], ["A", "B"]) == 0
    @test rank_list_distance(["A", "B"], ["B", "A"]) > 0
end

@testset "hermite / legendre weights integrate to ~1" begin
    ηs, w = hermite_nodes(0.0, 1.0; order = 16)
    @test isapprox(sum(w), 1.0; atol = 1e-3)
    σs, wσ = legendre_nodes(0.02, 1.0; order = 16)
    @test all(0.02 .<= σs .<= 1.0)
    @test isapprox(sum(wσ), 0.98; atol = 0.02)  # length of interval
end
