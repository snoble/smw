# Scoring rules for the Summer Movie Wager.
#
# Each Top-10 pick gets the single highest applicable rule:
#   13  correct #1 or #10
#   10  correct #2–#9
#    7  one spot off
#    5  two spots off
#    3  anywhere else in Top 10
#    0  missed Top 10
# Dark horses: +1 each if they land in the Top 10.

"""Points for one ranked pick given its predicted rank and actual rank (or `nothing` if outside Top 10)."""
function score_pick(predicted_rank::Integer, actual_rank::Union{Integer,Nothing})
    if actual_rank === nothing
        return 0
    end
    diff = abs(Int(predicted_rank) - Int(actual_rank))
    if diff == 0
        return (predicted_rank == 1 || predicted_rank == 10) ? 13 : 10
    elseif diff == 1
        return 7
    elseif diff == 2
        return 5
    else
        return 3
    end
end

"""
Score a player's full list against a final Top-10 ranking.

`picks` is a `PlayerPicks`. `final_ranking` is a Vector of film titles in order
(#1 first … #10 last). Films not in the Top 10 score 0 for ranked picks;
each dark horse in the Top 10 adds 1.
"""
function score_list(picks::PlayerPicks, final_ranking::AbstractVector{<:AbstractString})
    actual = Dict{String,Int}(title => i for (i, title) in enumerate(final_ranking))
    total = 0
    for (rank, film) in picks.ranked
        total += score_pick(rank, get(actual, film, nothing))
    end
    top10 = Set(final_ranking)
    for film in picks.dark_horses
        if film in top10
            total += 1
        end
    end
    return total
end

"""
Competition ranking with shared ranks (1, 2, 2, 4 style).

Returns a Dict player => (score, rank).
"""
function shared_ranks(scores::AbstractDict{<:AbstractString,<:Integer})
    ordered = sort(collect(scores); by = x -> (-x[2], x[1]))
    ranks = Dict{String,Tuple{Int,Int}}()
    i = 1
    while i <= length(ordered)
        player, score = ordered[i]
        j = i
        while j <= length(ordered) && ordered[j][2] == score
            j += 1
        end
        for k in i:(j - 1)
            ranks[ordered[k][1]] = (score, i)
        end
        i = j
    end
    return ranks
end

"""Score every player and return shared-rank standings."""
function standings(
    all_picks::AbstractDict{<:AbstractString,PlayerPicks},
    final_ranking::AbstractVector{<:AbstractString},
)
    scores = Dict{String,Int}(p => score_list(pk, final_ranking) for (p, pk) in all_picks)
    return shared_ranks(scores)
end

"""
Rank films by gross descending. Stable sort keeps input order on exact ties.

Returns a Vector of titles, highest gross first. Pass `n` to truncate (e.g. Top 10).
"""
function rank_by_gross(
    films::AbstractVector{<:AbstractString},
    grosses::AbstractVector{<:Real};
    n::Union{Integer,Nothing} = nothing,
)
    @assert length(films) == length(grosses)
    order = sortperm(collect(grosses); rev = true, alg = Base.Sort.DEFAULT_STABLE)
    ranked = films[order]
    return n === nothing ? ranked : ranked[1:min(Int(n), length(ranked))]
end
