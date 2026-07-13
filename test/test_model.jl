@testset "cumulative_gross" begin
    @test cumulative_gross(100.0, 0.5, 1.0) ≈ 100.0
    @test cumulative_gross(100.0, 0.5, 2.0) ≈ 150.0
    @test cumulative_gross(100.0, 0.5, 0.0) == 0.0
    @test cumulative_gross(100.0, 0.5, -1.0) == 0.0
    # d → 1 limit: O * t
    @test cumulative_gross(50.0, 1.0, 3.0) ≈ 150.0
    @test cumulative_gross(50.0, 1.0 - 1e-15, 2.0) ≈ 100.0
end

@testset "season_total banked + future" begin
    @test season_total(100.0, 0.5, 2.0) ≈ 150.0
    @test season_total(100.0, 0.5, 2.0; banked = 0.0, t_now = 1.0) ≈ 150.0
    @test season_total(100.0, 0.5, 2.0; banked = 50.0, t_now = 0.0) ≈ 150.0

    C = 253_000_000.0
    d = 0.55
    t_now = 8.0
    t_cut = 16.0
    G = season_total(1.0, d, t_cut; banked = C, t_now = t_now)
    @test G > C
    @test G ≈ C * (1 - d^t_cut) / (1 - d^t_now)
    @test season_total(1.0, d, 7.0; banked = C, t_now = 8.0) == C

    # Moana-style mid-opening pin floor
    C_early = 43_000_000.0
    t_early = 0.4
    t_long = 8.4
    G_raw = C_early * (1 - d^t_long) / (1 - d^t_early)
    G_pin = season_total(1.0, d, t_long; banked = C_early, t_now = t_early)
    @test G_raw / C_early > 4
    @test G_pin ≈ C_early * (1 - d^t_long) / (1 - d^1.0)
    @test G_pin / C_early < 3
    @test G_pin > C_early

    # t_cut between t_now and the 1-week pin floor → just banked
    @test season_total(1.0, d, 0.8; banked = C_early, t_now = 0.3) == C_early
end

@testset "unreleased_prior branches" begin
    curated = Film("Curated", Date(2026, 8, 1), false, 0.0, Date(2026, 7, 1), "animation", "", 40.0)
    type_fb = Film("TypeFB", Date(2026, 8, 1), false, 0.0, Date(2026, 7, 1), "horror", "", missing)
    unknown = Film("Unknown", Date(2026, 8, 1), false, 0.0, Date(2026, 7, 1), "doc", "", missing)
    zero_open = Film("Zero", Date(2026, 8, 1), false, 0.0, Date(2026, 7, 1), "comedy", "", 0.0)

    pc = unreleased_prior(curated)
    @test pc.μ_logO ≈ log(40e6)
    @test pc.σ_logO == SMW.UNRELEASED_LOGO_STD_CURATED

    pt = unreleased_prior(type_fb)
    @test pt.μ_logO ≈ log(SMW.UNRELEASED_OPENING_PRIORS["horror"])
    @test pt.σ_logO == SMW.UNRELEASED_LOGO_STD

    pu = unreleased_prior(unknown)
    @test pu.μ_logO ≈ log(12_000_000.0)

    pz = unreleased_prior(zero_open)
    @test pz.μ_logO ≈ log(SMW.UNRELEASED_OPENING_PRIORS["comedy"])
end

@testset "fit_type_priors pooled + typed" begin
    # Two films of same type → typed branch; one singleton type → pooled branch
    hist = DataFrame(
        year = [2019, 2019, 2019, 2019, 2018, 2018],
        title = ["A1", "A1", "A2", "A2", "B1", "B1"],
        type = ["animation", "animation", "animation", "animation", "oddity", "oddity"],
        week = [1, 2, 1, 2, 1, 2],
        cumulative_gross = [100e6, 150e6, 80e6, 120e6, 10e6, 15e6],
        final_gross = [200e6, 200e6, 160e6, 160e6, 40e6, 40e6],
    )
    priors = fit_type_priors(hist)
    @test haskey(priors, "__pooled__")
    @test haskey(priors, "animation")
    @test haskey(priors, "oddity")
    # animation has 2 films → own means; oddity has 1 → pooled values
    @test priors["oddity"].μ_logO == priors["__pooled__"].μ_logO
    @test priors["animation"].μ_logO != priors["__pooled__"].μ_logO ||
          priors["animation"].σ_logO != priors["__pooled__"].σ_logO

    # Unknown type falls back to pooled
    p = SMW.prior_for("nope", priors)
    @test p == priors["__pooled__"]
end

@testset "observed_floors + observed_times" begin
    season = load_season(DATA)
    floors = observed_floors(season)
    times = observed_times(season)
    @test floors["Moana"] >= 43_000_000
    @test times["Moana"] > 0
    @test times["Moana"] < 1.0  # mid-opening as of latest weekly

    # Observation with zero gross is skipped in times; older t not preferred
    films = [Film("Z", Date(2026, 5, 1), true, 10.0, Date(2026, 5, 8), "drama", "", missing)]
    obs = [
        Observation("Z", Date(2026, 5, 15), 0.0, 2.0),
        Observation("Z", Date(2026, 5, 8), 5.0, 1.0),
        Observation("Z", Date(2026, 5, 22), 20.0, 3.0),
    ]
    mini = SeasonData(films, obs, Dict{String,PlayerPicks}(), DataFrame())
    @test observed_floors(mini)["Z"] == 20.0
    @test observed_times(mini)["Z"] == 3.0
end

@testset "build_array_model overrides" begin
    season = load_season(DATA)
    title = "Spider-Man: Brand New Day"
    overrides = Dict{String,NamedTuple}(
        title => (logO_mean = log(200e6), logO_std = 0.2, G_mean = 500e6, G_std = 50e6),
        "The Odyssey" => (logO_mean = log(90e6),),  # default σ
        "Toy Story 5" => (G_mean = 400e6,),  # G override only (default σ)
    )
    inputs = build_array_model(season; overrides)
    @test inputs.n == length(season.films)
    @test length(inputs.titles) == inputs.n
    @test !isnothing(inputs.model)

    # Unreleased without override still gets unreleased_prior path
    inputs2 = build_array_model(season)
    @test inputs2.n == length(season.films)
end

@testset "sample_posterior + season_gross_draws" begin
    season = load_season(DATA)
    overrides = Dict{String,NamedTuple}(
        "Spider-Man: Brand New Day" => (logO_mean = log(180e6), logO_std = 0.25, G_mean = 450e6),
    )
    post = sample_posterior(season; overrides, n_samples = 40, seed = 7, progress = false)
    @test post.n == length(season.films)
    @test size(post.chain, 1) == 40

    G0 = season_gross_draws(post)  # no floors/times
    @test size(G0) == (post.n, 40)
    @test all(G0 .>= 0)

    G1 = season_gross_draws(
        post;
        floors = observed_floors(season),
        times = observed_times(season),
    )
    @test size(G1) == size(G0)
    moana = findfirst(==("Moana"), post.titles)
    @test median(G1[moana, :]) < 200e6  # pin floor keeps Moana sane
    @test median(G1[moana, :]) > observed_floors(season)["Moana"]
end

@testset "prior predictive" begin
    season = load_season(DATA)
    G = prior_predictive_grosses(season; n_draws = 50, seed = 7)
    @test all(G .>= 0)
    @test mean(G .> 1e9) < 0.2
end

@testset "simulate-and-recover (synthetic NUTS)" begin
    Random.seed!(123)
    true_O = [80_000_000.0, 40_000_000.0]
    true_d = [0.55, 0.45]
    ts = [1.0, 3.0, 1.0, 4.0]
    idx = [1, 1, 2, 2]
    obs = [cumulative_gross(true_O[idx[k]], true_d[idx[k]], ts[k]) * exp(0.02 * randn()) for k in 1:4]

    n = 2
    μ_logO = log.(true_O)
    σ_logO = fill(0.5, n)
    μ_logit_d = [log(d / (1 - d)) for d in true_d]
    σ_logit_d = fill(0.5, n)
    tcuts = [8.0, 8.0]
    model = SMW.RunCurveModelArrays(
        n,
        μ_logO,
        σ_logO,
        μ_logit_d,
        σ_logit_d,
        tcuts,
        idx,
        ts,
        log.(obs),
        Int[],
        Float64[],
        Float64[],
    )
    chain = sample(model, NUTS(0.65), 300; progress = false)
    df = DataFrame(chain)
    for i in 1:2
        Os = exp.(df[!, Symbol("logO[$i]")])
        ds = 1 ./ (1 .+ exp.(-df[!, Symbol("logit_d[$i]")]))
        @test quantile(Os, 0.05) <= true_O[i] <= quantile(Os, 0.95)
        @test quantile(ds, 0.05) <= true_d[i] <= quantile(ds, 0.95)
    end
end
