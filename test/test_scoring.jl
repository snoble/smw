@testset "score_pick rules" begin
    @test score_pick(1, 1) == 13
    @test score_pick(10, 10) == 13
    @test score_pick(5, 5) == 10
    @test score_pick(5, 4) == 7
    @test score_pick(5, 3) == 5
    @test score_pick(5, 8) == 3
    @test score_pick(5, nothing) == 0
    @test score_pick(2, 2) == 10
    @test score_pick(9, 9) == 10
end

@testset "score_list + dark horses" begin
    picks = PlayerPicks(
        "Alice",
        [(1, "A"), (2, "B"), (3, "C"), (4, "D"), (5, "E"), (6, "F"), (7, "G"), (8, "H"), (9, "I"), (10, "J")],
        ["X", "Y", "Z"],
    )
    ranking = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "X"]  # Z/Y miss; X dark horse hits
    # Perfect #1–#9 + #10 miss (J) + dark horse X → 13+10*8+10? wait #2-9 are 10 each = 80, #1=13, #10 predicted J actual nothing = 0, +1 dark
    # ranks: A1→13, B2→10, C3→10, D4→10, E5→10, F6→10, G7→10, H8→10, I9→10, J10→0 + X dark = 1
    @test score_list(picks, ranking) == 13 + 8 * 10 + 0 + 1
end

@testset "shared_ranks + standings" begin
    scores = Dict("A" => 40, "B" => 40, "C" => 30, "D" => 20)
    ranks = shared_ranks(scores)
    @test ranks["A"] == (40, 1)
    @test ranks["B"] == (40, 1)
    @test ranks["C"] == (30, 3)
    @test ranks["D"] == (20, 4)

    picks = Dict(
        "A" => PlayerPicks("A", [(1, "F1")], String[]),
        "B" => PlayerPicks("B", [(1, "F2")], String[]),
    )
    st = standings(picks, ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10"])
    @test st["A"][1] == 13  # predicted #1, actual #1
    @test st["B"][1] == 7   # predicted #1, actual #2 → one spot off
    @test st["A"][2] == 1
    @test st["B"][2] == 2
end

@testset "rank_by_gross" begin
    films = ["a", "b", "c"]
    g = [10, 30, 20]
    @test rank_by_gross(films, g) == ["b", "c", "a"]
    @test rank_by_gross(films, g; n = 2) == ["b", "c"]
    @test rank_by_gross(films, g; n = 99) == ["b", "c", "a"]
    # Stable ties keep input order
    @test rank_by_gross(["x", "y"], [5, 5]) == ["x", "y"]
end
