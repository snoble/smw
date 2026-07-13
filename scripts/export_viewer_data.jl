#!/usr/bin/env julia
# Export full-field posteriors into notebooks/smw2026_wasm.jl (WasmTarget-safe).
#
# WasmTarget cannot run Turing. Precompute a coarse grid over the high-leverage
# unreleased openings (same five knobs as notebooks/smw2026.jl), then ship numeric
# matrices + short title strings; format rows at runtime.
#
#   nix-shell --run 'julia --project scripts/export_viewer_data.jl'

using SMW
using Statistics

const ROOT = normpath(joinpath(@__DIR__, ".."))
const OUT_NB = joinpath(ROOT, "notebooks", "smw2026_wasm.jl")
const OUT_SIDE = joinpath(ROOT, "notebooks", "generated", "viewer_data.jl")

# Coarse grids — product must stay small enough for a local export.
# Defaults (180 / 85 / 40 / 45 / 30) are included so the site opens on CSV priors.
const SPIDEY_M = Int[100, 180, 250]
const ODYSSEY_M = Int[60, 85, 120]
const PAW_M = Int[30, 40]
const MUTINY_M = Int[30, 45]
const INSIDIOUS_M = Int[20, 30]
const N_SAMPLES = 100

const N_SP = length(SPIDEY_M)
const N_OD = length(ODYSSEY_M)
const N_PAW = length(PAW_M)
const N_MU = length(MUTINY_M)
const N_IN = length(INSIDIOUS_M)
const N_SCEN = N_SP * N_OD * N_PAW * N_MU * N_IN

"""1-based multi-index → flat scenario id (1…N_SCEN)."""
function scenario_id(sp::Int, od::Int, paw::Int, mu::Int, ins::Int)::Int
    return ((((sp - 1) * N_OD + (od - 1)) * N_PAW + (paw - 1)) * N_MU + (mu - 1)) * N_IN + ins
end

season = load_season(joinpath(ROOT, "data"))
titles = [f.title for f in season.films]
players = sort(collect(keys(season.picks)))
floors = observed_floors(season)
times = observed_times(season)
banked = [Float64(get(floors, t, 0.0)) for t in titles]

n_play = length(players)
n_film = length(titles)

win_sole = zeros(N_SCEN, n_play)
win_shared = zeros(N_SCEN, n_play)
mean_score = zeros(N_SCEN, n_play)
top10 = zeros(N_SCEN, n_film)
p_first = zeros(N_SCEN, n_film)
med_G = zeros(N_SCEN, n_film)
lo_G = zeros(N_SCEN, n_film)
hi_G = zeros(N_SCEN, n_film)

println("Exporting $N_SCEN scenarios × $N_SAMPLES draws ($n_film films)…")
let si = 0
    for (isp, sp) in enumerate(SPIDEY_M)
        for (iod, od) in enumerate(ODYSSEY_M)
            for (ipaw, paw) in enumerate(PAW_M)
                for (imu, mu) in enumerate(MUTINY_M)
                    for (iin, ins) in enumerate(INSIDIOUS_M)
                        si += 1
                        @assert si == scenario_id(isp, iod, ipaw, imu, iin)
                        overrides = Dict{String,NamedTuple}(
                            "Spider-Man: Brand New Day" => (logO_mean = log(sp * 1e6), logO_std = 0.2),
                            "The Odyssey" => (logO_mean = log(od * 1e6), logO_std = 0.35),
                            "PAW Patrol: The Dino Movie" => (logO_mean = log(paw * 1e6), logO_std = 0.35),
                            "Mutiny" => (logO_mean = log(mu * 1e6), logO_std = 0.35),
                            "Insidious: Out of the Further" => (logO_mean = log(ins * 1e6), logO_std = 0.35),
                        )
                        println(
                            "[$si/$N_SCEN] Spidey=\$$(sp)M Odyssey=\$$(od)M PAW=\$$(paw)M Mutiny=\$$(mu)M Insidious=\$$(ins)M",
                        )
                        posterior = sample_posterior(
                            season;
                            overrides,
                            n_samples = N_SAMPLES,
                            seed = 1000 + si,
                            progress = false,
                        )
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
                end
            end
        end
    end
end

esc_jl(s) = replace(s, '\\' => "\\\\", '"' => "\\\"")

function jl_int_matrix(M)
    rows = ["    " * join(string.(Int.(M[i, :])), " ") for i in 1:size(M, 1)]
    "Int[\n" * join(rows, "\n") * "\n]"
end

function jl_str_vec(xs)
    "String[\n" * join(["    \"" * esc_jl(s) * "\"" for s in xs], ",\n") * "\n]"
end

m_of(x) = round(Int, x / 1e6)
banked_m = [m_of(b) for b in banked]
med_m = [m_of(med_G[si, fi]) for si in 1:N_SCEN, fi in 1:n_film]
lo_m = [m_of(lo_G[si, fi]) for si in 1:N_SCEN, fi in 1:n_film]
hi_m = [m_of(hi_G[si, fi]) for si in 1:N_SCEN, fi in 1:n_film]
top10_pct = [round(Int, 10 * round(100 * top10[si, fi]; digits = 1)) for si in 1:N_SCEN, fi in 1:n_film]
first_pct = [round(Int, 10 * round(100 * p_first[si, fi]; digits = 1)) for si in 1:N_SCEN, fi in 1:n_film]

order = zeros(Int, N_SCEN, n_film)
for s in 1:N_SCEN
    order[s, :] = sortperm(@view(med_G[s, :]); rev = true)
end

fmt_pct(p) = string(round(100 * p; digits = 1)) * "%"
function standings_line(s)
    ord = sortperm(@view(win_shared[s, :]); rev = true)
    parts = [
        "$(players[pi]): sole $(fmt_pct(win_sole[s, pi])), tied $(fmt_pct(win_shared[s, pi])), avg $(round(mean_score[s, pi]; digits=1))"
        for pi in ord
    ]
    join(parts, " · ")
end
standings = [standings_line(s) for s in 1:N_SCEN]
# Chunk standings into a Vector{String} constant — avoids a 200-branch if/else in WASM.
standings_vec = "String[\n" * join(["    \"" * esc_jl(s) * "\"" for s in standings], ",\n") * "\n]"

# Defaults match Pluto notebook CSV priors
default_sp = findfirst(==(180), SPIDEY_M)
default_od = findfirst(==(85), ODYSSEY_M)
default_paw = findfirst(==(40), PAW_M)
default_mu = findfirst(==(45), MUTINY_M)
default_in = findfirst(==(30), INSIDIOUS_M)
@assert all(!isnothing, (default_sp, default_od, default_paw, default_mu, default_in))

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

Season total = already banked + positive remaining. Opening sliders are a **precomputed
sensitivity grid** (Wasm cannot re-fit Turing live). Released films stay pinned to observed
grosses. Moana-style mid-opening pins floor at 1 week.

Draws/scenario: $(N_SAMPLES). Scenarios: $(N_SCEN). Cutoff: Sep 7.
\"\"\"

# ╔═╡ a0000000-0000-0000-0000-000000000002
begin
	using PlutoUI: Slider as UISlider
	const SPIDEY_M = Int[$(join(SPIDEY_M, ", "))]
	const ODYSSEY_M = Int[$(join(ODYSSEY_M, ", "))]
	const PAW_M = Int[$(join(PAW_M, ", "))]
	const MUTINY_M = Int[$(join(MUTINY_M, ", "))]
	const INSIDIOUS_M = Int[$(join(INSIDIOUS_M, ", "))]
	const N_SP = $(N_SP)
	const N_OD = $(N_OD)
	const N_PAW = $(N_PAW)
	const N_MU = $(N_MU)
	const N_IN = $(N_IN)
	const N_FILM = $(n_film)
	const TITLES = $(jl_str_vec(titles))
	const BANKED_M = Int[$(join(string.(banked_m), ", "))]
	const ORDER = $(jl_int_matrix(order))
	const MED_M = $(jl_int_matrix(med_m))
	const LO_M = $(jl_int_matrix(lo_m))
	const HI_M = $(jl_int_matrix(hi_m))
	const TOP10_T = $(jl_int_matrix(top10_pct))
	const FIRST_T = $(jl_int_matrix(first_pct))
	const STANDINGS = $(standings_vec)
end

# ╔═╡ a0000000-0000-0000-0000-000000000003
md\"\"\"
## Opening assumptions (\\\$M)
Spider-Man · Odyssey · PAW Patrol · Mutiny · Insidious
\"\"\"

# ╔═╡ a0000000-0000-0000-0000-000000000004
@bind sp_i UISlider(1:$(N_SP), default=$(default_sp), show_value=true)

# ╔═╡ a0000000-0000-0000-0000-000000000014
@bind od_i UISlider(1:$(N_OD), default=$(default_od), show_value=true)

# ╔═╡ a0000000-0000-0000-0000-000000000015
@bind paw_i UISlider(1:$(N_PAW), default=$(default_paw), show_value=true)

# ╔═╡ a0000000-0000-0000-0000-000000000016
@bind mu_i UISlider(1:$(N_MU), default=$(default_mu), show_value=true)

# ╔═╡ a0000000-0000-0000-0000-000000000017
@bind in_i UISlider(1:$(N_IN), default=$(default_in), show_value=true)

# ╔═╡ a0000000-0000-0000-0000-000000000005
function scenario_id(sp::Int64, od::Int64, paw::Int64, mu::Int64, ins::Int64)::Int64
	return ((((sp - Int64(1)) * Int64(N_OD) + (od - Int64(1))) * Int64(N_PAW) + (paw - Int64(1))) * Int64(N_MU) + (mu - Int64(1))) * Int64(N_IN) + ins
end

# ╔═╡ a0000000-0000-0000-0000-000000000006
function openings_label(sp::Int64, od::Int64, paw::Int64, mu::Int64, ins::Int64)::String
	return "Spidey " * string(SPIDEY_M[sp]) * "M · Odyssey " * string(ODYSSEY_M[od]) *
		"M · PAW " * string(PAW_M[paw]) * "M · Mutiny " * string(MUTINY_M[mu]) *
		"M · Insidious " * string(INSIDIOUS_M[ins]) * "M"
end

# ╔═╡ a0000000-0000-0000-0000-000000000018
begin
	scen = scenario_id(Int64(sp_i), Int64(od_i), Int64(paw_i), Int64(mu_i), Int64(in_i))
	openings_label(Int64(sp_i), Int64(od_i), Int64(paw_i), Int64(mu_i), Int64(in_i))
end

# ╔═╡ a0000000-0000-0000-0000-000000000007
md\"\"\"
## Player outcomes
**sole** = alone in first · **tied** = sole or shared first (how the site shows ranks) · **avg** = mean final score
\"\"\"

# ╔═╡ a0000000-0000-0000-0000-000000000008
standings_for(scen::Int64)::String = STANDINGS[scen]

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
Local Pluto notebook (`notebooks/smw2026.jl`) has continuous sliders, full tables, and charts.
\"\"\"

# ╔═╡ Cell order:
# ╟─a0000000-0000-0000-0000-000000000001
# ╟─a0000000-0000-0000-0000-000000000002
# ╟─a0000000-0000-0000-0000-000000000003
# ╠═a0000000-0000-0000-0000-000000000004
# ╠═a0000000-0000-0000-0000-000000000014
# ╠═a0000000-0000-0000-0000-000000000015
# ╠═a0000000-0000-0000-0000-000000000016
# ╠═a0000000-0000-0000-0000-000000000017
# ╟─a0000000-0000-0000-0000-000000000005
# ╟─a0000000-0000-0000-0000-000000000006
# ╠═a0000000-0000-0000-0000-000000000018
# ╟─a0000000-0000-0000-0000-000000000007
# ╟─a0000000-0000-0000-0000-000000000008
# ╠═a0000000-0000-0000-0000-000000000009
# ╟─a0000000-0000-0000-0000-00000000000a
# ╠═a0000000-0000-0000-0000-00000000000b
# ╟─a0000000-0000-0000-0000-00000000000c
# ╟─a0000000-0000-0000-0000-00000000000d
# ╟─a0000000-0000-0000-0000-00000000000e
# ╠═a0000000-0000-0000-0000-00000000000f
# ╟─a0000000-0000-0000-0000-000000000010
# ╟─a0000000-0000-0000-0000-000000000011
# ╠═a0000000-0000-0000-0000-000000000012
# ╟─a0000000-0000-0000-0000-000000000013
"""

mkpath(dirname(OUT_SIDE))
open(OUT_NB, "w") do io
    write(io, nb)
end

# Sidecar for debugging / non-notebook consumers
open(OUT_SIDE, "w") do io
    println(io, "# Auto-generated sidecar (notebook has data inlined).")
    println(io, "const SPIDEY_M = Int[", join(SPIDEY_M, ", "), "]")
    println(io, "const ODYSSEY_M = Int[", join(ODYSSEY_M, ", "), "]")
    println(io, "const PAW_M = Int[", join(PAW_M, ", "), "]")
    println(io, "const MUTINY_M = Int[", join(MUTINY_M, ", "), "]")
    println(io, "const INSIDIOUS_M = Int[", join(INSIDIOUS_M, ", "), "]")
    println(io, "const N_SCEN = ", N_SCEN)
    println(io, "const PLAYERS = ", players)
end

def_si = scenario_id(default_sp, default_od, default_paw, default_mu, default_in)
println("Wrote ", OUT_NB)
println("Films: ", n_film, "  scenarios: ", N_SCEN)
println("Default scen ", def_si, ": ", standings[def_si])
moana = findfirst(==("Moana"), titles)
println(
    "Moana default med=",
    med_m[def_si, moana],
    "M  [",
    lo_m[def_si, moana],
    "-",
    hi_m[def_si, moana],
    "]",
)
println("Rank1 default: ", titles[order[def_si, 1]], " med=", med_m[def_si, order[def_si, 1]], "M")
