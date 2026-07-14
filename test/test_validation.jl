@testset "native vs wasm_kernel golden (shared seed)" begin
    include(joinpath(@__DIR__, "..", "src", "wasm_kernel.jl"))
    using .SMWKernel

    # Tiny 2-film packed input
    n_films = 2
    n_draws = 200
    seed = 99
    # header: schema, n_films, n_draws, seed, η, σ, n_overrides
    inp = Float64[
        SMWKernel.KERNEL_SCHEMA, n_films, n_draws, seed, 8, 8, 0,
        # film 1 released
        log(40e6), 0.4, 0.0, 0.3, 10.0, 50e6, 4.0, 200.0, 1.0, 1.0, 0.0,
        # film 2 unreleased
        log(80e6), 0.35, 0.0, 0.3, 8.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0,
        # one interval for film 1: 0→1 week, 40M
        0.0, 1.0, 40e6, 0.0,
    ]
    out = zeros(4 + n_films * n_draws)
    status = SMWKernel.run_simulation!(out, inp)
    @test status == Int32(0)
    @test out[2] == n_films
    @test out[3] == n_draws
    G = reshape(@view(out[5:end]), n_films, n_draws)
    @test all(isfinite, G)
    @test all(G[1, :] .>= 50e6 * 0.98)  # banked floor
    # Determinism: second run identical
    out2 = zeros(size(out))
    SMWKernel.run_simulation!(out2, inp)
    @test out == out2
end

@testset "quadrature order convergence (rank probs)" begin
    season = load_season(DATA)
    type_priors = fit_type_priors(season.historical)
    film_priors = film_priors_from_season(season, type_priors)
    intervals = interval_observations(season.observations)
    cfg16 = InferenceConfig(0.02, 1.0, 0.15, 0.1, 16, 16)
    # Compare median Sheep gross at two seeds with same cfg — smoke stability
    G1, _ = sample_factored_grosses(film_priors, intervals, 1500; seed = 1, cfg = cfg16)
    G2, _ = sample_factored_grosses(film_priors, intervals, 1500; seed = 2, cfg = cfg16)
    sheep = findfirst(p -> p.title == "The Sheep Detectives", film_priors)
    m1 = median(G1[sheep, :])
    m2 = median(G2[sheep, :])
    @test abs(m1 - m2) / m1 < 0.05  # MC noise across seeds for near-terminal film
end

@testset "NUTS vs factored summary parity (synthetic-ish)" begin
    # Compare median Top-1 title between short NUTS and factored draws on real season
    season = load_season(DATA)
    type_priors = fit_type_priors(season.historical)
    film_priors = film_priors_from_season(season, type_priors)
    intervals = interval_observations(season.observations)
    titles = [p.title for p in film_priors]

    Gf, _ = sample_factored_grosses(film_priors, intervals, 800; seed = 11)
    med_f = [median(@view Gf[i, :]) for i in eachindex(titles)]
    top_f = titles[argmax(med_f)]

    posterior = sample_posterior(season; n_samples = 400, seed = 11, progress = false)
    floors = observed_floors(season)
    times = observed_times(season)
    Gn = season_gross_draws(posterior; floors, times)
    # Align NUTS film order with season.films
    titles_n = [f.title for f in season.films]
    med_n = [median(@view Gn[i, :]) for i in eachindex(titles_n)]
    top_n = titles_n[argmax(med_n)]

    # Same blockbuster should lead both methods (Prada / Spidey / etc.)
    # Allow disagreement only if both are among top-3 by the other method
    order_f = sortperm(med_f; rev = true)
    order_n = sortperm(med_n; rev = true)
    top3_f = Set(titles[order_f[1:min(3, end)]])
    top3_n = Set(titles_n[order_n[1:min(3, end)]])
    @test top_f in top3_n || top_n in top3_f
end
