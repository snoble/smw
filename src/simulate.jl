struct SimulationResult
    titles::Vector{String}
    players::Vector{String}
    G::Matrix{Float64}                 # films × draws
    rank_prob::Matrix{Float64}         # films × 10  P(film finishes at rank r)
    top10_prob::Vector{Float64}        # P(film in Top 10)
    scores::Matrix{Float64}            # players × draws
    win_sole::Vector{Float64}          # P(sole first)
    win_shared::Vector{Float64}        # P(sole or tied first)
end

"""
Monte-Carlo readout: for each posterior draw of season grosses, rank → score → tally.
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
            shared[findfirst(==(w), players)] += 1
        end
    end

    return SimulationResult(
        titles,
        players,
        G,
        rank_counts ./ n_draws,
        top10_counts ./ n_draws,
        scores,
        sole ./ n_draws,
        shared ./ n_draws,
    )
end

function simulate_outcomes(season::SeasonData, posterior::NamedTuple; kwargs...)
    G = season_gross_draws(posterior)
    return simulate_outcomes(posterior.titles, G, season.picks; kwargs...)
end
