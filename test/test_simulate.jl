@testset "simulate outcomes shape + scenarios" begin
    season = load_season(DATA)
    n = length(season.films)
    G = prior_predictive_grosses(season; n_draws = 80, seed = 3)
    titles = [f.title for f in season.films]
    result = simulate_outcomes(titles, G, season.picks)
    @test size(result.rank_prob) == (n, 10)
    @test length(result.top10_prob) == n
    @test size(result.scores, 1) == 6
    @test sum(result.win_sole) <= 1.0 + 1e-9
    @test !isempty(result.win_scenarios)
    for s in result.win_scenarios
        @test length(s.ranking) == 10
        @test s.n_wins >= 1
        @test 1 <= s.draw <= size(result.G, 2)
        @test s.score == score_list(season.picks[s.player], s.ranking)
        all_scores = Dict(p => score_list(pk, s.ranking) for (p, pk) in season.picks)
        @test s.score == maximum(values(all_scores))
    end
    for (i, p) in enumerate(result.players)
        if result.win_shared[i] > 0
            @test any(s -> s.player == p, result.win_scenarios)
        end
    end
end

@testset "simulate_outcomes via posterior NamedTuple" begin
    season = load_season(DATA)
    post = sample_posterior(season; n_samples = 30, seed = 11, progress = false)
    sim = simulate_outcomes(season, post)
    @test length(sim.titles) == length(season.films)
    @test size(sim.G, 2) == 30
end

@testset "tied wins + print_win_scenarios" begin
    titles = ["F$i" for i in 1:12]
    # Two draws: draw 1 → A sole win; draw 2 → A and B tie
    G = zeros(12, 2)
    G[:, 1] = reverse(collect(1.0:12.0)) .* 1e6
    G[:, 2] = reverse(collect(1.0:12.0)) .* 1e6

    # Craft picks so scores tie on both draws
    picks = Dict(
        "A" => PlayerPicks("A", [(i, "F$i") for i in 1:10], String[]),
        "B" => PlayerPicks("B", [(i, "F$i") for i in 1:10], String[]),
        "C" => PlayerPicks("C", [(i, "F$(11 - i)") for i in 1:10], String[]),
    )
    sim = simulate_outcomes(titles, G, picks)
    # A and B identical lists → always tied when they beat C
    @test any(!isempty(s.tied_with) for s in sim.win_scenarios)

    buf = IOBuffer()
    print_win_scenarios(buf, sim)
    out = String(take!(buf))
    @test occursin("MOST REPRESENTATIVE TOP 10", out)
    @test occursin("tied with", out) || occursin("sole first", out)

    buf2 = IOBuffer()
    print_win_scenarios(buf2, sim; min_win_prob = 1.1)  # filter everyone out
    out2 = String(take!(buf2))
    @test occursin("no players above min_win_prob", out2)

    # stdout overload (1-arg method) — redirect to a real file stream
    path, file = mktemp()
    try
        redirect_stdout(file) do
            print_win_scenarios(sim; min_win_prob = 0.0)
        end
        flush(file)
        close(file)
        @test occursin("MOST REPRESENTATIVE TOP 10", read(path, String))
    finally
        isfile(path) && rm(path; force = true)
    end
end

@testset "sole winner path" begin
    titles = ["T$i" for i in 1:10]
    G = reshape(Float64.(10:-1:1), 10, 1) .* 1e6
    picks = Dict(
        "Winner" => PlayerPicks("Winner", [(i, "T$i") for i in 1:10], String[]),
        "Loser" => PlayerPicks("Loser", [(i, "T$(11 - i)") for i in 1:10], String[]),
    )
    sim = simulate_outcomes(titles, G, picks)
    @test sim.win_sole[findfirst(==("Winner"), sim.players)] == 1.0
    @test only(s for s in sim.win_scenarios if s.player == "Winner").tied_with == String[]

    buf = IOBuffer()
    print_win_scenarios(buf, sim)
    @test occursin("sole first", String(take!(buf)))
end
