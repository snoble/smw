#!/usr/bin/env julia
# Export full-field posteriors into notebooks/smw2026_wasm.jl (WasmTarget-safe).
#
# Precomputes a coarse opening grid, then ships **preformatted monospace report
# blocks** (player table, win scenarios, field table, rank heatmap) so the static
# site can look like the Pluto terminal readouts without Turing / Makie in WASM.
#
#   nix-shell --run 'julia --project scripts/export_viewer_data.jl'

using SMW
using Statistics

const ROOT = normpath(joinpath(@__DIR__, ".."))
const OUT_NB = joinpath(ROOT, "notebooks", "smw2026_wasm.jl")
const OUT_SIDE = joinpath(ROOT, "notebooks", "generated", "viewer_data.jl")

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

scenario_id(sp, od, paw, mu, ins) =
    ((((sp - 1) * N_OD + (od - 1)) * N_PAW + (paw - 1)) * N_MU + (mu - 1)) * N_IN + ins

season = load_season(joinpath(ROOT, "data"))
titles = [f.title for f in season.films]
players_sorted = sort(collect(keys(season.picks)))
floors = observed_floors(season)
times = observed_times(season)
banked = [Float64(get(floors, t, 0.0)) for t in titles]
n_film = length(titles)

player_blocks = Vector{String}(undef, N_SCEN)
win_blocks = Vector{String}(undef, N_SCEN)
field_blocks = Vector{String}(undef, N_SCEN)
heat_blocks = Vector{String}(undef, N_SCEN)

pct(p) = string(round(100 * p; digits = 1)) * "%"
money(x) = x > 0 ? string(round(Int, x / 1e6)) * "M" : "--"

function format_players(sim)
    io = IOBuffer()
    println(io, "PLAYER OUTCOMES")
    println(io, rpad("player", 10), " ", rpad("sole", 7), rpad("tied", 7), rpad("avg", 6), rpad("p10", 6), rpad("p50", 6), "p90")
    println(io, "-"^56)
    for i in sortperm(sim.win_shared; rev = true)
        println(
            io,
            rpad(sim.players[i], 10),
            " ",
            rpad(pct(sim.win_sole[i]), 7),
            rpad(pct(sim.win_shared[i]), 7),
            rpad(string(round(mean(sim.scores[i, :]); digits = 1)), 6),
            rpad(string(round(quantile(sim.scores[i, :], 0.1); digits = 1)), 6),
            rpad(string(round(quantile(sim.scores[i, :], 0.5); digits = 1)), 6),
            string(round(quantile(sim.scores[i, :], 0.9); digits = 1)),
        )
    end
    return String(take!(io))
end

function format_wins(sim)
    io = IOBuffer()
    print_win_scenarios(io, sim; min_win_prob = 0.0)
    return String(take!(io))
end

function format_field(sim, banked_vec)
    med = [median(@view sim.G[i, :]) for i in 1:length(sim.titles)]
    lo = [quantile(@view(sim.G[i, :]), 0.05) for i in 1:length(sim.titles)]
    hi = [quantile(@view(sim.G[i, :]), 0.95) for i in 1:length(sim.titles)]
    order = sortperm(med; rev = true)
    io = IOBuffer()
    println(io, "FULL FIELD by median season G")
    println(io, lpad("#", 2), "  ", rpad("Film", 36), " ", rpad("banked", 6), " ", rpad("med", 5), " ", rpad("[5-95%]", 11), " ", rpad("Top10", 6), " #1")
    println(io, "-"^86)
    for (rank, i) in enumerate(order)
        band = "[" * string(round(Int, lo[i] / 1e6)) * "-" * string(round(Int, hi[i] / 1e6)) * "]"
        println(
            io,
            lpad(string(rank), 2),
            ". ",
            rpad(sim.titles[i], 36),
            " ",
            rpad(money(banked_vec[i]), 6),
            " ",
            rpad(money(med[i]), 5),
            " ",
            rpad(band, 11),
            " ",
            rpad(pct(sim.top10_prob[i]), 6),
            " ",
            pct(sim.rank_prob[i, 1]),
        )
    end
    return String(take!(io))
end

const HEAT = collect(" .:-=+*#%@")  # 10 levels
function format_heat(sim)
    med = [median(@view sim.G[i, :]) for i in 1:length(sim.titles)]
    keep = findall(sim.top10_prob .> 0.05)
    by_med = sortperm(med; rev = true)[1:min(15, length(med))]
    idx = sort(unique(vcat(keep, by_med)); by = i -> -med[i])
    length(idx) > 18 && (idx = idx[1:18])
    io = IOBuffer()
    println(io, "P(finish at rank r)  darker = more probable")
    println(io, "     ", join([lpad(string(r), 3) for r in 1:10], ""))
    println(io, "     ", "-"^30)
    for i in idx
        cells = Char[]
        for r in 1:10
            p = sim.rank_prob[i, r]
            lvl = clamp(round(Int, p * 9) + 1, 1, 10)
            push!(cells, HEAT[lvl])
            push!(cells, HEAT[lvl])
            push!(cells, HEAT[lvl])
        end
        println(io, rpad(sim.titles[i], 36), " ", String(cells), "  T10=", pct(sim.top10_prob[i]))
    end
    println(io, "scale: '", String(HEAT), "' = 0% … 100%")
    return String(take!(io))
end

println("Exporting $N_SCEN scenarios × $N_SAMPLES draws ($n_film films)…")
let si = 0
    for (isp, sp) in enumerate(SPIDEY_M),
        (iod, od) in enumerate(ODYSSEY_M),
        (ipaw, paw) in enumerate(PAW_M),
        (imu, mu) in enumerate(MUTINY_M),
        (iin, ins) in enumerate(INSIDIOUS_M)

        si += 1
        @assert si == scenario_id(isp, iod, ipaw, imu, iin)
        overrides = Dict{String,NamedTuple}(
            "Spider-Man: Brand New Day" => (logO_mean = log(sp * 1e6), logO_std = 0.2),
            "The Odyssey" => (logO_mean = log(od * 1e6), logO_std = 0.35),
            "PAW Patrol: The Dino Movie" => (logO_mean = log(paw * 1e6), logO_std = 0.35),
            "Mutiny" => (logO_mean = log(mu * 1e6), logO_std = 0.35),
            "Insidious: Out of the Further" => (logO_mean = log(ins * 1e6), logO_std = 0.35),
        )
        println("[$si/$N_SCEN] Spidey=\$$(sp)M Odyssey=\$$(od)M PAW=\$$(paw)M Mutiny=\$$(mu)M Insidious=\$$(ins)M")
        posterior = sample_posterior(
            season;
            overrides,
            n_samples = N_SAMPLES,
            seed = 1000 + si,
            progress = false,
        )
        G = season_gross_draws(posterior; floors, times)
        sim = simulate_outcomes(titles, G, season.picks)
        player_blocks[si] = format_players(sim)
        win_blocks[si] = format_wins(sim)
        field_blocks[si] = format_field(sim, banked)
        heat_blocks[si] = format_heat(sim)
    end
end

# Long report strings fail Snapshot's WasmTarget oracle (>~500 chars). Ship them as
# JSON for the HTML polish layer; the notebook only emits a short SCEN=N label.
const OUT_JSON = joinpath(ROOT, "site", "smw2026_reports.json")

function json_escape(s::AbstractString)
    s = replace(s, '\\' => "\\\\")
    s = replace(s, '"' => "\\\"")
    s = replace(s, '\n' => "\\n")
    s = replace(s, '\r' => "\\r")
    s = replace(s, '\t' => "\\t")
    return s
end

function write_reports_json(path, def_si, players, wins, heat, field)
    open(path, "w") do io
        print(io, "{\"default\":", def_si)
        for (key, xs) in (
            ("players", players),
            ("wins", wins),
            ("heat", heat),
            ("field", field),
        )
            print(io, ",\"", key, "\":[")
            for (i, s) in enumerate(xs)
                i > 1 && print(io, ",")
                print(io, "\"", json_escape(s), "\"")
            end
            print(io, "]")
        end
        print(io, "}")
    end
end

default_sp = findfirst(==(180), SPIDEY_M)
default_od = findfirst(==(85), ODYSSEY_M)
default_paw = findfirst(==(40), PAW_M)
default_mu = findfirst(==(45), MUTINY_M)
default_in = findfirst(==(30), INSIDIOUS_M)
def_si = scenario_id(default_sp, default_od, default_paw, default_mu, default_in)

sp_legend = join(["**$(i)**=\\\$$(v)M" for (i, v) in enumerate(SPIDEY_M)], " · ")
od_legend = join(["**$(i)**=\\\$$(v)M" for (i, v) in enumerate(ODYSSEY_M)], " · ")
paw_legend = join(["**$(i)**=\\\$$(v)M" for (i, v) in enumerate(PAW_M)], " · ")
mu_legend = join(["**$(i)**=\\\$$(v)M" for (i, v) in enumerate(MUTINY_M)], " · ")
in_legend = join(["**$(i)**=\\\$$(v)M" for (i, v) in enumerate(INSIDIOUS_M)], " · ")

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

Opening sliders pick a **precomputed** scenario (Wasm cannot re-fit Turing live). Released
films stay pinned to observed grosses.

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
	const N_OD = $(N_OD)
	const N_PAW = $(N_PAW)
	const N_MU = $(N_MU)
	const N_IN = $(N_IN)
end

# ╔═╡ a0000000-0000-0000-0000-000000000003
md\"\"\"
## Opening assumptions

**Spider-Man** $(sp_legend)

**Odyssey** $(od_legend)

**PAW Patrol** $(paw_legend)

**Mutiny** $(mu_legend)

**Insidious** $(in_legend)
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
	local sid = scenario_id(sp, od, paw, mu, ins)
	return "SCEN=" * string(sid) * " · Spidey " * string(SPIDEY_M[sp]) * "M · Odyssey " * string(ODYSSEY_M[od]) *
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
**sole** = alone in first · **tied** = sole or shared first · score quantiles from the same draws
\"\"\"

# ╔═╡ a0000000-0000-0000-0000-000000000009
"@smw:players"

# ╔═╡ a0000000-0000-0000-0000-00000000001a
md\"\"\"
## Most representative Top 10 where each player wins
Medoid of posterior draws where they finish sole **or tied** first — the typical world in which they win.
\"\"\"

# ╔═╡ a0000000-0000-0000-0000-00000000001b
"@smw:wins"

# ╔═╡ a0000000-0000-0000-0000-00000000001c
md\"\"\"
## Rank heatmap
P(finish at rank 1…10) for competitive films (Top10 > 5% or top 15 by median).
\"\"\"

# ╔═╡ a0000000-0000-0000-0000-00000000001d
"@smw:heat"

# ╔═╡ a0000000-0000-0000-0000-00000000001e
md\"\"\"
## Full Labor Day field
Sorted by median season gross.
\"\"\"

# ╔═╡ a0000000-0000-0000-0000-00000000001f
"@smw:field"

# ╔═╡ a0000000-0000-0000-0000-000000000013
md\"\"\"
---
Continuous sliders + Makie charts: local Pluto notebook `notebooks/smw2026.jl`.
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
# ╠═a0000000-0000-0000-0000-000000000009
# ╟─a0000000-0000-0000-0000-00000000001a
# ╠═a0000000-0000-0000-0000-00000000001b
# ╟─a0000000-0000-0000-0000-00000000001c
# ╠═a0000000-0000-0000-0000-00000000001d
# ╟─a0000000-0000-0000-0000-00000000001e
# ╠═a0000000-0000-0000-0000-00000000001f
# ╟─a0000000-0000-0000-0000-000000000013
"""

mkpath(dirname(OUT_SIDE))
mkpath(dirname(OUT_JSON))
open(OUT_NB, "w") do io
    write(io, nb)
end
write_reports_json(OUT_JSON, def_si, player_blocks, win_blocks, heat_blocks, field_blocks)
open(OUT_SIDE, "w") do io
    println(io, "# Auto-generated sidecar")
    println(io, "const N_SCEN = ", N_SCEN)
    println(io, "const PLAYERS = ", players_sorted)
end

println("Wrote ", OUT_NB)
println("Wrote ", OUT_JSON)
println("Default scenario ", def_si)
println(first(split(player_blocks[def_si], '\n'; limit = 4)))
println("---")
println(first(split(win_blocks[def_si], '\n'; limit = 6)))
