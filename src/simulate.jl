struct SimulationResult
    titles::Vector{String}
    players::Vector{String}
    G::Matrix{Float64}                 # films × draws
    rank_prob::Matrix{Float64}         # films × 10  P(film finishes at rank r)
    top10_prob::Vector{Float64}        # P(film in Top 10)
    scores::Matrix{Float64}            # players × draws
    win_sole::Vector{Float64}          # P(sole first)
    win_shared::Vector{Float64}        # P(sole or tied first)
    """
    For each player with ≥1 sole-or-tied win: the Top-10 from the **medoid** winning
    draw (gross vector closest to the coordinate-wise median of that player's win draws).
    That is the most representative realized list where they win.
    """
    win_scenarios::Vector{NamedTuple{
        (:player, :ranking, :n_wins, :score, :tied_with, :draw),
        Tuple{String,Vector{String},Int,Int,Vector{String},Int},
    }}
end

"""
Monte-Carlo readout: for each posterior draw of season grosses, rank → score → tally.

For every player who ever finishes sole or tied first, also records the Top-10 from the
medoid of those winning draws (most representative list where they win).
"""
function simulate_outcomes(
    titles::Vector{String},
    G::Matrix{Float64},
    picks::AbstractDict{<:AbstractString,PlayerPicks};
    top_n::Int = 10,
)
    n_films, n_draws = size(G)
    @assert n_films == length(titles)
    players = sort(collect(keys(picks)))
    n_players = length(players)

    rank_counts = zeros(Float64, n_films, top_n)
    top10_counts = zeros(Float64, n_films)
    scores = Matrix{Float64}(undef, n_players, n_draws)
    sole = zeros(Float64, n_players)
    shared = zeros(Float64, n_players)
    win_draws = [Int[] for _ in 1:n_players]

    title_idx = Dict(t => i for (i, t) in enumerate(titles))

    for draw in 1:n_draws
        ranking = rank_by_gross(titles, @view(G[:, draw]); n = top_n)
        for (r, film) in enumerate(ranking)
            i = title_idx[film]
            rank_counts[i, r] += 1
            top10_counts[i] += 1
        end
        sc = Dict{String,Int}()
        for (p, pk) in picks
            sc[p] = score_list(pk, ranking)
        end
        for (pi, player) in enumerate(players)
            scores[pi, draw] = sc[player]
        end
        best = maximum(values(sc))
        winners = [p for (p, s) in sc if s == best]
        if length(winners) == 1
            sole[findfirst(==(winners[1]), players)] += 1
        end
        for w in winners
            pi = findfirst(==(w), players)
            shared[pi] += 1
            push!(win_draws[pi], draw)
        end
    end

    scenarios = NamedTuple{
        (:player, :ranking, :n_wins, :score, :tied_with, :draw),
        Tuple{String,Vector{String},Int,Int,Vector{String},Int},
    }[]
    for (pi, player) in enumerate(players)
        idxs = win_draws[pi]
        isempty(idxs) && continue
        # Coordinate-wise median gross among this player's winning worlds
        medG = [median(@view G[i, idxs]) for i in 1:n_films]
        # Medoid draw: minimize squared distance to that median (most typical win)
        best_draw = idxs[1]
        best_dist = Inf
        for j in idxs
            dist = 0.0
            for i in 1:n_films
                δ = G[i, j] - medG[i]
                dist += δ * δ
            end
            if dist < best_dist
                best_dist = dist
                best_draw = j
            end
        end
        ranking = rank_by_gross(titles, @view(G[:, best_draw]); n = top_n)
        sc = Dict{String,Int}(p => score_list(pk, ranking) for (p, pk) in picks)
        my = sc[player]
        tied = sort([p for (p, s) in sc if s == my && p != player])
        push!(
            scenarios,
            (
                player = player,
                ranking = ranking,
                n_wins = length(idxs),
                score = my,
                tied_with = tied,
                draw = best_draw,
            ),
        )
    end
    sort!(scenarios; by = s -> -s.n_wins)

    return SimulationResult(
        titles,
        players,
        G,
        rank_counts ./ n_draws,
        top10_counts ./ n_draws,
        scores,
        sole ./ n_draws,
        shared ./ n_draws,
        scenarios,
    )
end

function simulate_outcomes(season::SeasonData, posterior::NamedTuple; kwargs...)
    G = season_gross_draws(
        posterior;
        floors = observed_floors(season),
        times = observed_times(season),
    )
    return simulate_outcomes(posterior.titles, G, season.picks; kwargs...)
end

"""Pretty-print representative win lists to `io` (CLI / Pluto `with_terminal`)."""
function print_win_scenarios(io::IO, sim::SimulationResult; min_win_prob::Float64 = 0.0)
    n_draws = size(sim.G, 2)
    println(io, "MOST REPRESENTATIVE TOP 10 WHERE EACH PLAYER WINS")
    println(io, "(medoid of draws where they finish sole or tied first)")
    println(io, "-"^78)
    shown = 0
    for s in sim.win_scenarios
        p_win = s.n_wins / n_draws
        p_win < min_win_prob && continue
        shown += 1
        tie_note = isempty(s.tied_with) ? "sole first" : ("tied with " * join(s.tied_with, ", "))
        println(
            io,
            s.player,
            "  P(win)=",
            round(100 * p_win; digits = 1),
            "%  score=",
            s.score,
            "  (",
            tie_note,
            ")  [",
            s.n_wins,
            " win draws]",
        )
        for (r, film) in enumerate(s.ranking)
            println(io, "   ", lpad(string(r), 2), ". ", film)
        end
        println(io)
    end
    if shown == 0
        println(io, "(no players above min_win_prob=$(min_win_prob))")
    end
    return nothing
end

print_win_scenarios(sim::SimulationResult; kwargs...) =
    print_win_scenarios(stdout, sim; kwargs...)
