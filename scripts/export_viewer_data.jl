#!/usr/bin/env julia
# Export full-field posteriors into notebooks/smw2026_wasm.jl (WasmTarget-safe).
#
# WasmTarget cannot ship giant string-literal tables (stack overflow / GlobalRef).
# Ship numeric matrices + short title strings; format rows at runtime.
#
#   nix-shell --run 'julia --project scripts/export_viewer_data.jl'

using SMW
using Statistics

const ROOT = normpath(joinpath(@__DIR__, ".."))
const OUT_NB = joinpath(ROOT, "notebooks", "smw2026_wasm.jl")

season = load_season(joinpath(ROOT, "data"))
titles = [f.title for f in season.films]
players = sort(collect(keys(season.picks)))
floors = observed_floors(season)
times = observed_times(season)
banked = [Float64(get(floors, t, 0.0)) for t in titles]

spidey_openings = [100, 150, 180, 220]
n_samples = 300
n_scen = length(spidey_openings)
n_play = length(players)
n_film = length(titles)

win_sole = zeros(n_scen, n_play)
win_shared = zeros(n_scen, n_play)
mean_score = zeros(n_scen, n_play)
top10 = zeros(n_scen, n_film)
p_first = zeros(n_scen, n_film)
med_G = zeros(n_scen, n_film)
lo_G = zeros(n_scen, n_film)
hi_G = zeros(n_scen, n_film)

for (si, open_m) in enumerate(spidey_openings)
    overrides = Dict{String,NamedTuple}(
        "Spider-Man: Brand New Day" => (logO_mean = log(open_m * 1e6), logO_std = 0.2),
        "The Odyssey" => (logO_mean = log(80e6), logO_std = 0.35),
    )
    println("Sampling Spider-Man=\$$(open_m)M …")
    posterior = sample_posterior(season; overrides, n_samples, progress = true)
    G = season_gross_draws(posterior; floors, times)
    sim = simulate_outcomes(titles, G, season.picks)
    for (pi, p) in enumerate(players)
        j = findfirst(==(p), sim.players)
        win_sole[si, pi] = sim.win_sole[j]
        win_shared[si, pi] = sim.win_shared[j]
        mean_score[si, pi] = mean(sim.scores[j, :])
    end
    top10[si, :] .= sim.top10_prob
    p_first[si, :] .= sim.rank_prob[:, 1]
    for fi in 1:n_film
        col = @view G[fi, :]
        med_G[si, fi] = median(col)
        lo_G[si, fi] = quantile(col, 0.05)
        hi_G[si, fi] = quantile(col, 0.95)
    end
end

esc_jl(s) = replace(s, '\\' => "\\\\", '"' => "\\\"")

function jl_f64_matrix(M)
    rows = ["    " * join(string.(round.(Float64.(M[i, :]); digits = 4)), " ") for i in 1:size(M, 1)]
    "Float64[\n" * join(rows, "\n") * "\n]"
end

function jl_int_matrix(M)
    rows = ["    " * join(string.(Int.(M[i, :])), " ") for i in 1:size(M, 1)]
    "Int[\n" * join(rows, "\n") * "\n]"
end

function jl_str_vec(xs)
    "String[\n" * join(["    \"" * esc_jl(s) * "\"" for s in xs], ",\n") * "\n]"
end

# Millions (rounded) for compact display. banked 0 → "—" in viewer; med 0 → "$0M".
m_of(x) = round(Int, x / 1e6)
banked_m = [m_of(b) for b in banked]
med_m = [m_of(med_G[si, fi]) for si in 1:n_scen, fi in 1:n_film]
lo_m = [m_of(lo_G[si, fi]) for si in 1:n_scen, fi in 1:n_film]
hi_m = [m_of(hi_G[si, fi]) for si in 1:n_scen, fi in 1:n_film]
top10_pct = [round(Int, 10 * round(100 * top10[si, fi]; digits = 1)) for si in 1:n_scen, fi in 1:n_film] # tenths
first_pct = [round(Int, 10 * round(100 * p_first[si, fi]; digits = 1)) for si in 1:n_scen, fi in 1:n_film]
# ORDER[scen, rank] = film index (1-based) sorted by median desc
order = zeros(Int, n_scen, n_film)
for si in 1:n_scen
    order[si, :] = sortperm(@view(med_G[si, :]); rev = true)
end

# Standings: medium if/else strings still compile fine
fmt_pct(p) = string(round(100 * p; digits = 1)) * "%"
function standings_line(si)
    ord = sortperm(@view(win_shared[si, :]); rev = true)
    parts = [
        "$(players[pi]): sole $(fmt_pct(win_sole[si, pi])), tied $(fmt_pct(win_shared[si, pi])), avg $(round(mean_score[si, pi]; digits=1))"
        for pi in ord
    ]
    join(parts, " · ")
end
standings = [standings_line(si) for si in 1:n_scen]
standings_branches = join([
    "    scen == $(si) && return \"$(esc_jl(standings[si]))\""
    for si in 1:n_scen
], "\n")

nb = """
### A Pluto.jl notebook ###
# v1.0.3

using Markdown
using InteractiveUtils

macro bind(def, element)
    #! format: off
    return quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = \$(esc(element))
        global \$(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end

# ╔═╡ a0000000-0000-0000-0000-000000000001
md\"\"\"
# Summer Movie Wager 2026

Labor Day domestic box-office posterior for the **full $(n_film)-film field**, then wager
outcomes for all six players.

Season total = already banked + positive remaining. Spider-Man hasn't opened — the slider
is only a **sensitivity control** over four opening scenarios; released films stay pinned
to observed grosses.

Draws/scenario: $(n_samples). Cutoff: Sep 7.
\"\"\"

# ╔═╡ a0000000-0000-0000-0000-000000000002
begin
	using PlutoUI: Slider as UISlider
	const OPENINGS = Int[$(join(spidey_openings, ", "))]
	const N_FILM = $(n_film)
	const TITLES = $(jl_str_vec(titles))
	const BANKED_M = Int[$(join(string.(banked_m), ", "))]
	const ORDER = $(jl_int_matrix(order))
	const MED_M = $(jl_int_matrix(med_m))
	const LO_M = $(jl_int_matrix(lo_m))
	const HI_M = $(jl_int_matrix(hi_m))
	const TOP10_T = $(jl_int_matrix(top10_pct))
	const FIRST_T = $(jl_int_matrix(first_pct))
end

# ╔═╡ a0000000-0000-0000-0000-000000000003
md\"\"\"
## Spider-Man opening (sensitivity only)
**1**=\\\$$(spidey_openings[1])M · **2**=\\\$$(spidey_openings[2])M · **3**=\\\$$(spidey_openings[3])M · **4**=\\\$$(spidey_openings[4])M
\"\"\"

# ╔═╡ a0000000-0000-0000-0000-000000000004
@bind scen UISlider(1:4, default=3, show_value=true)

# ╔═╡ a0000000-0000-0000-0000-000000000005
opening_for(scen::Int64)::Int64 = OPENINGS[scen]

# ╔═╡ a0000000-0000-0000-0000-000000000006
opening_for(Int64(scen))

# ╔═╡ a0000000-0000-0000-0000-000000000007
md\"\"\"
## Player outcomes
**sole** = alone in first · **tied** = sole or shared first (how the site shows ranks) · **avg** = mean final score
\"\"\"

# ╔═╡ a0000000-0000-0000-0000-000000000008
function standings_for(scen::Int64)::String
$(standings_branches)
    return ""
end

# ╔═╡ a0000000-0000-0000-0000-000000000009
standings_for(Int64(scen))

# ╔═╡ a0000000-0000-0000-0000-00000000000a
md\"\"\"
## Full predicted Labor Day field ($(n_film) films)
Pick a predicted rank (1 = highest median season gross). Shows banked, median band, P(Top 10), P(#1).
\"\"\"

# ╔═╡ a0000000-0000-0000-0000-00000000000b
@bind rank UISlider(1:$(n_film), default=1, show_value=true)

# ╔═╡ a0000000-0000-0000-0000-00000000000c
function money(m::Int64)::String
    m == Int64(0) && return "--"
    return string(m) * "M"
end

# ╔═╡ a0000000-0000-0000-0000-00000000000d
function pct_t(t::Int64)::String
    whole = t ÷ Int64(10)
    frac = t - whole * Int64(10)
    return string(whole) * "." * string(frac) * "%"
end

# ╔═╡ a0000000-0000-0000-0000-00000000000e
function film_at(scen::Int64, rank::Int64)::String
    fi = ORDER[scen, rank]
    return string(rank) * ". " * TITLES[fi] *
        " | banked " * money(Int64(BANKED_M[fi])) *
        " | med " * money(Int64(MED_M[scen, fi])) *
        " (" * money(Int64(LO_M[scen, fi])) * "-" * money(Int64(HI_M[scen, fi])) * ")" *
        " | Top10 " * pct_t(Int64(TOP10_T[scen, fi])) *
        " | #1 " * pct_t(Int64(FIRST_T[scen, fi]))
end

# ╔═╡ a0000000-0000-0000-0000-00000000000f
film_at(Int64(scen), Int64(rank))

# ╔═╡ a0000000-0000-0000-0000-000000000010
md\"\"\"
### Nearby ranks (same scenario)
\"\"\"

# ╔═╡ a0000000-0000-0000-0000-000000000011
function nearby(scen::Int64, rank::Int64)::String
    lo = rank - Int64(2)
    if lo < Int64(1)
        lo = Int64(1)
    end
    hi = lo + Int64(4)
    if hi > N_FILM
        hi = N_FILM
        lo = hi - Int64(4)
        if lo < Int64(1)
            lo = Int64(1)
        end
    end
    out = film_at(scen, lo)
    i = lo + Int64(1)
    while i <= hi
        out = out * " || " * film_at(scen, i)
        i = i + Int64(1)
    end
    return out
end

# ╔═╡ a0000000-0000-0000-0000-000000000012
nearby(Int64(scen), Int64(rank))

# ╔═╡ a0000000-0000-0000-0000-000000000013
md\"\"\"
---
Local Pluto notebook (`notebooks/smw2026.jl`) has the full sortable table + charts.
\"\"\"

# ╔═╡ Cell order:
# ╟─a0000000-0000-0000-0000-000000000001
# ╠═a0000000-0000-0000-0000-000000000002
# ╟─a0000000-0000-0000-0000-000000000003
# ╠═a0000000-0000-0000-0000-000000000004
# ╠═a0000000-0000-0000-0000-000000000005
# ╠═a0000000-0000-0000-0000-000000000006
# ╟─a0000000-0000-0000-0000-000000000007
# ╠═a0000000-0000-0000-0000-000000000008
# ╠═a0000000-0000-0000-0000-000000000009
# ╟─a0000000-0000-0000-0000-00000000000a
# ╠═a0000000-0000-0000-0000-00000000000b
# ╠═a0000000-0000-0000-0000-00000000000c
# ╠═a0000000-0000-0000-0000-00000000000d
# ╠═a0000000-0000-0000-0000-00000000000e
# ╠═a0000000-0000-0000-0000-00000000000f
# ╟─a0000000-0000-0000-0000-000000000010
# ╠═a0000000-0000-0000-0000-000000000011
# ╠═a0000000-0000-0000-0000-000000000012
# ╟─a0000000-0000-0000-0000-000000000013
"""

open(OUT_NB, "w") do io
    write(io, nb)
end
println("Wrote ", OUT_NB)
println("Films: ", n_film)
println("Standings scen3: ", standings[3])
println("Rank1 scen3 film: ", titles[order[3, 1]], " med=", med_m[3, order[3, 1]], "M")
