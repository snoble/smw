using Test
using SMW
using Dates
using Distributions
using Random
using DataFrames
using Turing

const DATA = joinpath(@__DIR__, "..", "data")

@testset "cumulative_gross" begin
    @test cumulative_gross(100.0, 0.5, 1.0) ≈ 100.0
    @test cumulative_gross(100.0, 0.5, 2.0) ≈ 150.0
    @test cumulative_gross(100.0, 0.5, 0.0) == 0.0
end

@testset "season_total banked + future" begin
    # Unreleased: ordinary curve
    @test season_total(100.0, 0.5, 2.0) ≈ 150.0
    # Released: G = banked * (1 - d^t_cut) / (1 - d^t_now) >= banked
    C = 253_000_000.0
    d = 0.55
    t_now = 8.0
    t_cut = 16.0
    G = season_total(1.0, d, t_cut; banked = C, t_now = t_now)  # O unused when banked>0
    @test G > C
    @test G ≈ C * (1 - d^t_cut) / (1 - d^t_now)
    # Past cutoff: just banked
    @test season_total(1.0, d, 7.0; banked = C, t_now = 8.0) == C
    # Mid-opening-weekend weak gross must NOT 5–6× (Moana-style bug)
    C_early = 43_000_000.0
    t_early = 0.4
    t_long = 8.4
    G_raw = C_early * (1 - d^t_long) / (1 - d^t_early)  # singular-ish ratio ≈ 5×+
    G_pin = season_total(1.0, d, t_long; banked = C_early, t_now = t_early)
    @test G_raw / C_early > 4
    @test G_pin ≈ C_early * (1 - d^t_long) / (1 - d^1.0)
    @test G_pin / C_early < 3
    @test G_pin > C_early
end

@testset "score_pick rules" begin
    @test score_pick(1, 1) == 13
    @test score_pick(10, 10) == 13
    @test score_pick(5, 5) == 10
    @test score_pick(5, 4) == 7
    @test score_pick(5, 3) == 5
    @test score_pick(5, 8) == 3
    @test score_pick(5, nothing) == 0
end

@testset "golden standings 2026-07-13" begin
    season = load_season(DATA)
    # Provisional Top 10 from current cumulative grosses among released films with gross > 0
    released = filter(f -> f.released && f.cumulative_gross > 0, season.films)
    titles = [f.title for f in released]
    grosses = [f.cumulative_gross for f in released]
    ranking = rank_by_gross(titles, grosses; n = 10)

    expected_top10 = [
        "Toy Story 5",
        "Obsession",
        "The Devil Wears Prada 2",
        "Backrooms",
        "Star Wars: The Mandalorian and Grogu",
        "Disclosure Day",
        "Minions & Monsters",
        "Scary Movie",
        "Mortal Kombat II",
        "Supergirl",
    ]
    @test ranking == expected_top10

    expected = Dict(
        "Jeff" => 46,
        "Devindra" => 39,
        "Germain" => 39,
        "Peter" => 38,
        "David" => 36,
        "BJ" => 33,
    )
    for (player, pts) in expected
        @test score_list(season.picks[player], ranking) == pts
    end

    st = standings(season.picks, ranking)
    @test st["Jeff"] == (46, 1)
    @test st["Devindra"] == (39, 2)
    @test st["Germain"] == (39, 2)
    @test st["Peter"] == (38, 4)
end

@testset "data loaders" begin
    season = load_season(DATA)
    @test length(season.films) >= 20
    @test length(season.observations) >= 20
    @test length(season.picks) == 6
    @test t_cutoff(Date(2026, 8, 28)) ≈ run_weeks(Date(2026, 8, 28), SEASON_CUTOFF)
    # Unknown pick title should error
    @test_throws ErrorException load_picks(joinpath(DATA, "picks_2026.csv"), Film[])
    # Curated openings differentiate same-type unreleased titles
    paw = only(f for f in season.films if f.title == "PAW Patrol: The Dino Movie")
    coyote = only(f for f in season.films if f.title == "Coyote vs. Acme")
    @test !ismissing(paw.opening_prior_m) && !ismissing(coyote.opening_prior_m)
    @test paw.opening_prior_m > coyote.opening_prior_m
    @test unreleased_prior(paw).μ_logO > unreleased_prior(coyote).μ_logO
end

@testset "prior predictive sanity" begin
    season = load_season(DATA)
    G = prior_predictive_grosses(season; n_draws = 50, seed = 7)
    @test all(G .>= 0)
    # Not routinely > $1B
    @test mean(G .> 1e9) < 0.2
end

@testset "simulate-and-recover" begin
    Random.seed!(123)
    # Two synthetic films, known params, two observations each
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
        logOs = df[!, Symbol("logO[$i]")]
        logit_ds = df[!, Symbol("logit_d[$i]")]
        Os = exp.(logOs)
        ds = 1 ./ (1 .+ exp.(-logit_ds))
        # 90% credible interval should cover truth
        @test quantile(Os, 0.05) <= true_O[i] <= quantile(Os, 0.95)
        @test quantile(ds, 0.05) <= true_d[i] <= quantile(ds, 0.95)
    end
end

@testset "simulate outcomes shape" begin
    season = load_season(DATA)
    n = length(season.films)
    Random.seed!(1)
    # Fake posterior draws from prior predictive (fast)
    G = prior_predictive_grosses(season; n_draws = 80, seed = 3)
    titles = [f.title for f in season.films]
    result = simulate_outcomes(titles, G, season.picks)
    @test size(result.rank_prob) == (n, 10)
    @test length(result.top10_prob) == n
    @test size(result.scores, 1) == 6
    @test abs(sum(result.win_shared) - 1.0) < 1e-9 || sum(result.win_shared) >= 1.0 - 1e-9
    # win_shared sums to >= 1 because ties count multiple players; sole sums <= 1
    @test sum(result.win_sole) <= 1.0 + 1e-9
    @test !isempty(result.win_scenarios)
    for s in result.win_scenarios
        @test length(s.ranking) == 10
        @test s.n_wins >= 1
        @test 1 <= s.draw <= size(result.G, 2)
        @test s.score == score_list(season.picks[s.player], s.ranking)
        # Player is sole or tied first on their win list
        all_scores = Dict(p => score_list(pk, s.ranking) for (p, pk) in season.picks)
        @test s.score == maximum(values(all_scores))
    end
    # Every player with a shared win gets a scenario
    for (i, p) in enumerate(result.players)
        if result.win_shared[i] > 0
            @test any(s -> s.player == p, result.win_scenarios)
        end
    end
end
