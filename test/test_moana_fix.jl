@testset "Moana cartoon legs with OW pin" begin
    season = load_season(DATA)
    moana = only(f for f in season.films if f.title == "Moana")
    @test moana.type == "animation"
    moana_obs = filter(o -> o.film == "Moana", season.observations)
    @test !isempty(moana_obs)
    @test all(o -> o.t == 1.0, moana_obs)
    @test maximum(o.cumulative_gross for o in moana_obs) == 43_000_000
    @test length(moana_obs) == 1

    type_priors = fit_type_priors(season.historical)
    film_priors = film_priors_from_season(season, type_priors)
    intervals = interval_observations(season.observations)
    G, _ = sample_factored_grosses(film_priors, intervals, 5000; seed = 3)
    mi = findfirst(p -> p.title == "Moana", film_priors)
    si = findfirst(p -> p.title == "Supergirl", film_priors)
    qs = quantile(G[mi, :], [0.05, 0.5, 0.95])
    @test qs[1] >= 43e6
    # Cartoon legs, but OW pin keeps the old ~$180M+ upside from exploding
    @test qs[2] > 100e6
    @test qs[2] < 145e6
    @test qs[3] < 200e6
    # Should usually clear Supergirl's path
    @test mean(G[mi, :] .> G[si, :]) > 0.55
    @test median(G[mi, :]) > median(G[si, :])
end
