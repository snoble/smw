const SEASON_START = Date(2026, 4, 30)
const SEASON_CUTOFF = Date(2026, 9, 7)

struct Film
    title::String
    release_date::Date
    released::Bool
    cumulative_gross::Float64
    as_of::Date
    type::String
    notes::String
    """Expected opening-week domestic gross in millions USD; `missing` → type default."""
    opening_prior_m::Union{Missing,Float64}
end

struct Observation
    film::String
    date::Date
    cumulative_gross::Float64
    t::Float64  # fractional run-weeks since release
end

struct PlayerPicks
    player::String
    ranked::Vector{Tuple{Int,String}}  # (rank, title), ranks 1..10
    dark_horses::Vector{String}
end

struct SeasonData
    films::Vector{Film}
    observations::Vector{Observation}
    picks::Dict{String,PlayerPicks}
    historical::DataFrame
end

"""Run-weeks between release and `as_of` (fractional, 7-day weeks)."""
function run_weeks(release::Date, as_of::Date)
    days = Dates.value(as_of - release)
    return max(days / 7.0, 0.0)
end

"""Run-weeks a film gets before Labor Day cutoff."""
t_cutoff(release::Date) = run_weeks(release, SEASON_CUTOFF)

function load_films(path::AbstractString)
    df = CSV.read(path, DataFrame)
    has_opening = "opening_prior_m" in names(df)
    films = Film[]
    for row in eachrow(df)
        opening = if has_opening && !ismissing(row.opening_prior_m) && row.opening_prior_m !== ""
            Float64(row.opening_prior_m)
        else
            missing
        end
        push!(
            films,
            Film(
                String(row.title),
                Date(row.release_date),
                Bool(row.released),
                Float64(row.cumulative_gross),
                Date(row.as_of),
                String(row.type),
                ismissing(row.notes) ? "" : String(row.notes),
                opening,
            ),
        )
    end
    return films
end

function load_weekly(path::AbstractString, films::AbstractVector{Film})
    by_title = Dict(f.title => f for f in films)
    df = CSV.read(path, DataFrame)
    obs = Observation[]
    for row in eachrow(df)
        title = String(row.film)
        haskey(by_title, title) || error("weekly observation for unknown film: $title")
        release = by_title[title].release_date
        date = Date(row.date)
        push!(
            obs,
            Observation(title, date, Float64(row.cumulative_gross), run_weeks(release, date)),
        )
    end
    return obs
end

"""Fallback observations from films registry when a released film has no weekly rows."""
function fallback_observations(films::AbstractVector{Film}, weekly::AbstractVector{Observation})
    seen = Set(o.film for o in weekly)
    extras = Observation[]
    for f in films
        if f.released && f.cumulative_gross > 0 && !(f.title in seen)
            push!(
                extras,
                Observation(f.title, f.as_of, f.cumulative_gross, run_weeks(f.release_date, f.as_of)),
            )
        end
    end
    return extras
end

function load_picks(path::AbstractString, films::AbstractVector{Film})
    known = Set(f.title for f in films)
    df = CSV.read(path, DataFrame)
    by_player = Dict{String,NamedTuple{(:ranked, :dark),Tuple{Vector{Tuple{Int,String}},Vector{String}}}}()
    for row in eachrow(df)
        player = String(row.player)
        film = String(row.film)
        film in known || error("pick references unknown film: $film (player=$player)")
        if !haskey(by_player, player)
            by_player[player] = (ranked = Tuple{Int,String}[], dark = String[])
        end
        entry = by_player[player]
        if Bool(row.dark_horse)
            push!(entry.dark, film)
        else
            ismissing(row.rank) && error("non-dark-horse pick missing rank: $player / $film")
            push!(entry.ranked, (Int(row.rank), film))
        end
    end
    picks = Dict{String,PlayerPicks}()
    for (player, entry) in by_player
        ranked = sort(entry.ranked; by = first)
        picks[player] = PlayerPicks(player, ranked, entry.dark)
    end
    return picks
end

function load_historical(path::AbstractString)
    return CSV.read(path, DataFrame)
end

"""Load the full season bundle from a data directory."""
function load_season(data_dir::AbstractString = joinpath(@__DIR__, "..", "data"))
    films = load_films(joinpath(data_dir, "films_2026.csv"))
    weekly_path = joinpath(data_dir, "weekly_2026.csv")
    weekly = isfile(weekly_path) ? load_weekly(weekly_path, films) : Observation[]
    observations = vcat(weekly, fallback_observations(films, weekly))
    picks = load_picks(joinpath(data_dir, "picks_2026.csv"), films)
    historical = load_historical(joinpath(data_dir, "historical", "films_history.csv"))
    return SeasonData(films, observations, picks, historical)
end
