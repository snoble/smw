@testset "golden standings 2026-07-13" begin
    season = load_season(DATA)
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
