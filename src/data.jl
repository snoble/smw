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
    theaters::Union{Missing,Int}
    source::String
end

"""Backward-compatible constructor: theaters/source optional."""
function Observation(
    film::String,
    date::Date,
    cumulative_gross::Float64,
    t::Float64;
    theaters::Union{Missing,Int} = missing,
    source::String = "",
)
    return Observation(film, date, cumulative_gross, t, theaters, source)
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

"""
Observation-time run-weeks for likelihood / pinning.

Opening weekend (Fri–Sun, and the Monday report that usually closes OW) is
treated as a full exhibition week (`t = 1`). Fri–Sun is most of week-1 revenue,
so timestamping those rows at `days/7 ≈ 0.3–0.4` makes the curve think most of
the opening week is still ahead and overstates remaining upside.
"""
function observation_run_weeks(release::Date, as_of::Date)
    days = Dates.value(as_of - release)
    days < 0 && return 0.0
    # days 0..3 cover Fri open through the Monday OW print
    days <= 3 && return 1.0
    return days / 7.0
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

function _row_theaters(row)::Union{Missing,Int}
    if !hasproperty(row, :theaters) || ismissing(row.theaters) || row.theaters === ""
        return missing
    end
    return Int(row.theaters)
end

function _row_source(row)::String
    if !hasproperty(row, :source) || ismissing(row.source)
        return ""
    end
    return String(row.source)
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
            Observation(
                title,
                date,
                Float64(row.cumulative_gross),
                observation_run_weeks(release, date);
                theaters = _row_theaters(row),
                source = _row_source(row),
            ),
        )
    end
    return collapse_same_t_observations(obs)
end

"""Keep the latest / highest cumulative when several rows share the same `t`."""
function collapse_same_t_observations(obs::AbstractVector{Observation})
    by_key = Dict{Tuple{String,Float64},Observation}()
    for o in obs
        key = (o.film, o.t)
        if !haskey(by_key, key)
            by_key[key] = o
            continue
        end
        prev = by_key[key]
        better =
            o.cumulative_gross > prev.cumulative_gross ||
            (o.cumulative_gross == prev.cumulative_gross && o.date >= prev.date)
        if better
            by_key[key] = o
        end
    end
    return sort!(collect(values(by_key)); by = o -> (o.film, o.t, o.date))
end

"""Fallback observations from films registry when a released film has no weekly rows."""
function fallback_observations(films::AbstractVector{Film}, weekly::AbstractVector{Observation})
    seen = Set(o.film for o in weekly)
    extras = Observation[]
    for f in films
        if f.released && f.cumulative_gross > 0 && !(f.title in seen)
            push!(
                extras,
                Observation(
                    f.title,
                    f.as_of,
                    f.cumulative_gross,
                    observation_run_weeks(f.release_date, f.as_of);
                    theaters = missing,
                    source = "registry",
                ),
            )
        end
    end
    return extras
end

"""
Convert sorted cumulative rows per film into non-overlapping increments.

Returns a vector of named tuples
`(film, t_start, t_end, interval_gross, theaters_end)`.
The first interval for each film starts at `t_start = 0` (release).
"""
function interval_observations(obs::AbstractVector{Observation})
    by_film = Dict{String,Vector{Observation}}()
    for o in obs
        push!(get!(Vector{Observation}, by_film, o.film), o)
    end
    intervals = NamedTuple{
        (:film, :t_start, :t_end, :interval_gross, :theaters_end),
        Tuple{String,Float64,Float64,Float64,Union{Missing,Int}},
    }[]
    for (film, rows) in by_film
        sort!(rows; by = o -> (o.t, o.date))
        prev_t = 0.0
        prev_c = 0.0
        for o in rows
            o.t >= prev_t || continue
            interval_gross = max(0.0, o.cumulative_gross - prev_c)
            push!(
                intervals,
                (
                    film = film,
                    t_start = prev_t,
                    t_end = o.t,
                    interval_gross = interval_gross,
                    theaters_end = o.theaters,
                ),
            )
            prev_t = o.t
            prev_c = o.cumulative_gross
        end
    end
    return intervals
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
