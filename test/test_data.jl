@testset "run_weeks / t_cutoff" begin
    @test run_weeks(Date(2026, 7, 10), Date(2026, 7, 17)) ≈ 1.0
    @test run_weeks(Date(2026, 7, 17), Date(2026, 7, 10)) == 0.0  # before release
    @test t_cutoff(Date(2026, 8, 28)) ≈ run_weeks(Date(2026, 8, 28), SEASON_CUTOFF)
    @test SEASON_START == Date(2026, 4, 30)
    @test SEASON_CUTOFF == Date(2026, 9, 7)
    # Opening weekend calendar days map to a full exhibition week
    @test observation_run_weeks(Date(2026, 7, 10), Date(2026, 7, 10)) == 1.0  # Fri
    @test observation_run_weeks(Date(2026, 7, 10), Date(2026, 7, 12)) == 1.0  # Sun
    @test observation_run_weeks(Date(2026, 7, 10), Date(2026, 7, 13)) == 1.0  # Mon OW print
    @test observation_run_weeks(Date(2026, 7, 10), Date(2026, 7, 17)) ≈ 1.0
    @test observation_run_weeks(Date(2026, 7, 10), Date(2026, 7, 24)) ≈ 2.0
end

@testset "load_films variants" begin
    mktempdir() do dir
        # Full schema with missing notes + empty opening + curated opening
        path = joinpath(dir, "films.csv")
        open(path, "w") do io
            println(
                io,
                "title,release_date,released,cumulative_gross,as_of,type,opening_prior_m,notes",
            )
            println(io, "Alpha,2026-05-01,true,1000000,2026-07-01,drama,10,hit")
            println(io, "Beta,2026-08-01,false,0,2026-07-01,comedy,,")
            println(io, "Gamma,2026-08-15,false,0,2026-07-01,weird_type,,")
        end
        films = load_films(path)
        @test length(films) == 3
        @test films[1].opening_prior_m == 10.0
        @test films[1].notes == "hit"
        @test ismissing(films[2].opening_prior_m)
        @test films[2].notes == ""
        @test ismissing(films[3].opening_prior_m)

        # No opening_prior_m column at all
        path2 = joinpath(dir, "films_bare.csv")
        open(path2, "w") do io
            println(io, "title,release_date,released,cumulative_gross,as_of,type,notes")
            println(io, "Delta,2026-06-01,true,500000,2026-07-01,horror,")
        end
        bare = load_films(path2)
        @test length(bare) == 1
        @test ismissing(bare[1].opening_prior_m)
        @test bare[1].notes == ""
    end
end

@testset "load_weekly + fallback_observations" begin
    films = [
        Film("InWeekly", Date(2026, 5, 1), true, 1e6, Date(2026, 7, 1), "drama", "", missing),
        Film("OnlyRegistry", Date(2026, 5, 8), true, 2e6, Date(2026, 7, 1), "drama", "n", missing),
        Film("ZeroGross", Date(2026, 5, 15), true, 0.0, Date(2026, 7, 1), "drama", "", missing),
        Film("Unreleased", Date(2026, 8, 1), false, 0.0, Date(2026, 7, 1), "drama", "", 5.0),
    ]
    mktempdir() do dir
        # Backward-compatible schema (no theaters/source)
        weekly = joinpath(dir, "weekly.csv")
        open(weekly, "w") do io
            println(io, "film,date,cumulative_gross")
            println(io, "InWeekly,2026-05-08,500000")
            println(io, "InWeekly,2026-05-15,1000000")
        end
        obs = load_weekly(weekly, films)
        @test length(obs) == 2
        @test obs[1].film == "InWeekly"
        @test obs[1].t ≈ 1.0
        @test ismissing(obs[1].theaters)
        @test obs[1].source == ""

        # Extended schema with theaters + source
        weekly_ext = joinpath(dir, "weekly_ext.csv")
        open(weekly_ext, "w") do io
            println(io, "film,date,cumulative_gross,theaters,source")
            println(io, "InWeekly,2026-05-08,500000,3000,bom")
            println(io, "InWeekly,2026-05-15,1000000,2800,bom")
        end
        obs_ext = load_weekly(weekly_ext, films)
        @test obs_ext[1].theaters == 3000
        @test obs_ext[1].source == "bom"
        @test obs_ext[2].theaters == 2800

        extras = SMW.fallback_observations(films, obs)
        @test length(extras) == 1
        @test extras[1].film == "OnlyRegistry"
        @test extras[1].cumulative_gross == 2e6
        @test extras[1].source == "registry"

        @test_throws ErrorException load_weekly(weekly, Film[])  # unknown after empty known set
        # Explicit unknown title
        bad = joinpath(dir, "bad.csv")
        open(bad, "w") do io
            println(io, "film,date,cumulative_gross")
            println(io, "Nope,2026-05-08,1")
        end
        @test_throws ErrorException load_weekly(bad, films)
    end
end

@testset "interval_observations" begin
    obs = [
        Observation("A", Date(2026, 5, 8), 10.0, 1.0; theaters = 100, source = "bom"),
        Observation("A", Date(2026, 5, 15), 25.0, 2.0; theaters = 80, source = "bom"),
        Observation("B", Date(2026, 5, 8), 5.0, 0.5; theaters = missing, source = "est"),
    ]
    intervals = interval_observations(obs)
    a = filter(i -> i.film == "A", intervals)
    @test length(a) == 2
    @test a[1].t_start == 0.0
    @test a[1].t_end == 1.0
    @test a[1].interval_gross == 10.0
    @test a[1].theaters_end == 100
    @test a[2].t_start == 1.0
    @test a[2].t_end == 2.0
    @test a[2].interval_gross == 15.0
    @test a[2].theaters_end == 80
    b = only(i for i in intervals if i.film == "B")
    @test b.interval_gross == 5.0
    @test ismissing(b.theaters_end)
end

@testset "Sheep Detectives audit anchors" begin
    season = load_season(DATA)
    sheep = only(f for f in season.films if f.title == "The Sheep Detectives")
    @test sheep.release_date == Date(2026, 5, 8)
    @test sheep.type == "animation"
    sheep_obs = filter(o -> o.film == "The Sheep Detectives", season.observations)
    latest = argmax(o -> (o.date, o.t), sheep_obs)
    @test latest.theaters <= 200
    odyssey = only(f for f in season.films if f.title == "The Odyssey")
    @test odyssey.opening_prior_m == 105.0
end

@testset "load_picks errors + dark horses" begin
    films = [
        Film("A", Date(2026, 5, 1), true, 1.0, Date(2026, 7, 1), "drama", "", missing),
        Film("B", Date(2026, 5, 1), true, 1.0, Date(2026, 7, 1), "drama", "", missing),
        Film("C", Date(2026, 5, 1), true, 1.0, Date(2026, 7, 1), "drama", "", missing),
    ]
    mktempdir() do dir
        good = joinpath(dir, "picks.csv")
        open(good, "w") do io
            println(io, "player,rank,film,dark_horse")
            println(io, "P1,1,A,false")
            println(io, "P1,2,B,false")
            println(io, "P1,,C,true")
        end
        picks = load_picks(good, films)
        @test picks["P1"].ranked == [(1, "A"), (2, "B")]
        @test picks["P1"].dark_horses == ["C"]

        unknown = joinpath(dir, "unknown.csv")
        open(unknown, "w") do io
            println(io, "player,rank,film,dark_horse")
            println(io, "P1,1,Nope,false")
        end
        @test_throws ErrorException load_picks(unknown, films)

        missing_rank = joinpath(dir, "missing_rank.csv")
        open(missing_rank, "w") do io
            println(io, "player,rank,film,dark_horse")
            println(io, "P1,,A,false")
        end
        @test_throws ErrorException load_picks(missing_rank, films)
    end
end

@testset "load_season with and without weekly" begin
    season = load_season(DATA)
    @test length(season.films) >= 20
    @test length(season.observations) >= 20
    @test length(season.picks) == 6
    @test nrow(load_historical(joinpath(DATA, "historical", "films_history.csv"))) > 0

    mktempdir() do dir
        # Minimal season: copy films/picks/history, omit weekly → fallback path
        cp(joinpath(DATA, "films_2026.csv"), joinpath(dir, "films_2026.csv"))
        cp(joinpath(DATA, "picks_2026.csv"), joinpath(dir, "picks_2026.csv"))
        mkpath(joinpath(dir, "historical"))
        cp(
            joinpath(DATA, "historical", "films_history.csv"),
            joinpath(dir, "historical", "films_history.csv"),
        )
        s = load_season(dir)
        @test !isempty(s.films)
        @test !isempty(s.observations)  # fallbacks from released registry rows
        @test length(s.picks) == 6
    end
end

@testset "curated openings differentiate same-type titles" begin
    season = load_season(DATA)
    paw = only(f for f in season.films if f.title == "PAW Patrol: The Dino Movie")
    coyote = only(f for f in season.films if f.title == "Coyote vs. Acme")
    @test !ismissing(paw.opening_prior_m) && !ismissing(coyote.opening_prior_m)
    @test paw.opening_prior_m > coyote.opening_prior_m
    @test unreleased_prior(paw).μ_logO > unreleased_prior(coyote).μ_logO
end
