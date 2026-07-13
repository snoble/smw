### A Pluto.jl notebook ###
# v1.0.3

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    #! format: off
    return quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end

# ╔═╡ 11111111-1111-1111-1111-111111111111
begin
	import Pkg
	# Pluto cannot load a local package via its built-in package manager.
	# Activate the shared project environment at the repo root instead.
	root = normpath(joinpath(@__DIR__, ".."))
	Pkg.activate(root)
	Pkg.instantiate()
	using SMW
	using CairoMakie
	using Statistics
	using Dates
	using Serialization
	# Slider clashes with CairoMakie; with_terminal gives CLI-style monospaced output.
	using PlutoUI: Slider as UISlider, with_terminal
end

# ╔═╡ 22222222-2222-2222-2222-222222222222
md"""
# Summer Movie Wager 2026 — Bayesian outcomes

Posterior over the **full candidate field** through Labor Day (Sep 7), then wager scores
for all six players. Season total = **banked + positive remaining**.

**Opening sliders** below cover the unreleased titles that can actually move the Top 10 /
standings. Everything else uses `opening_prior_m` from `data/films_2026.csv`. Update
weekly CSVs, then re-run (or bump samples) to bust the cache.
"""

# ╔═╡ 33333333-3333-3333-3333-333333333333
md"""
## Controls

NUTS samples, then expected **opening-week** domestic gross (\$M) for high-leverage
unreleased films. Defaults match the CSV priors.
"""

# ╔═╡ 44444444-4444-4444-4444-444444444444
@bind n_samples UISlider(100:100:800, default=300, show_value=true)

# ╔═╡ 55555555-5555-5555-5555-555555555555
md"""
**Spider-Man: Brand New Day** opening (\$M)
"""

# ╔═╡ 55555555-5555-5555-5555-555555555556
@bind spidey_open UISlider(50:10:250, default=180, show_value=true)

# ╔═╡ 55555555-5555-5555-5555-555555555557
md"""
**The Odyssey** opening (\$M)
"""

# ╔═╡ 55555555-5555-5555-5555-555555555558
@bind odyssey_open UISlider(30:5:150, default=85, show_value=true)

# ╔═╡ 55555555-5555-5555-5555-555555555559
md"""
**PAW Patrol: The Dino Movie** opening (\$M)
"""

# ╔═╡ 55555555-5555-5555-5555-55555555555a
@bind paw_open UISlider(10:5:80, default=40, show_value=true)

# ╔═╡ 55555555-5555-5555-5555-55555555555b
md"""
**Mutiny** opening (\$M)
"""

# ╔═╡ 55555555-5555-5555-5555-55555555555c
@bind mutiny_open UISlider(10:5:90, default=45, show_value=true)

# ╔═╡ 55555555-5555-5555-5555-55555555555d
md"""
**Insidious: Out of the Further** opening (\$M)
"""

# ╔═╡ 55555555-5555-5555-5555-55555555555e
@bind insidious_open UISlider(5:5:60, default=30, show_value=true)

# ╔═╡ 66666666-6666-6666-6666-666666666666
md"""
Samples **$(n_samples)** · Spidey **\$$(spidey_open)M** · Odyssey **\$$(odyssey_open)M** ·
PAW **\$$(paw_open)M** · Mutiny **\$$(mutiny_open)M** · Insidious **\$$(insidious_open)M**
"""

# ╔═╡ 77777777-7777-7777-7777-777777777777
begin
	season = load_season(joinpath(root, "data"))
	function open_override(m; σ=0.35)
		(logO_mean = log(Float64(m) * 1_000_000), logO_std = σ)
	end
	overrides = Dict{String,NamedTuple}(
		"Spider-Man: Brand New Day" => open_override(spidey_open; σ=0.2),
		"The Odyssey" => open_override(odyssey_open),
		"PAW Patrol: The Dino Movie" => open_override(paw_open),
		"Mutiny" => open_override(mutiny_open),
		"Insidious: Out of the Further" => open_override(insidious_open),
	)
	mkpath(joinpath(root, "output"))
	cache_key = joinpath(
		root,
		"output",
		"posterior_v3_s$(n_samples)_sp$(spidey_open)_od$(odyssey_open)_paw$(paw_open)_mu$(mutiny_open)_in$(insidious_open).jls",
	)
	if isfile(cache_key)
		posterior = open(deserialize, cache_key, "r")
	else
		posterior = sample_posterior(season; overrides, n_samples=Int(n_samples), progress=false)
		open(io -> serialize(io, posterior), cache_key, "w")
	end
	sim = simulate_outcomes(season, posterior)
	nothing
end

# ╔═╡ 80808080-8080-8080-8080-808080808080
begin
	G = sim.G
	med = [median(@view G[i, :]) for i in 1:size(G, 1)]
	lo = [quantile(@view(G[i, :]), 0.05) for i in 1:size(G, 1)]
	hi = [quantile(@view(G[i, :]), 0.95) for i in 1:size(G, 1)]
	floors = observed_floors(season)
	times = observed_times(season)
	banked = [Float64(get(floors, t, 0.0)) for t in sim.titles]
	field_order = sortperm(med; rev=true)
	n_field = length(sim.titles)
	m_str(x) = x > 0 ? string(round(Int, x / 1e6)) * "M" : "—"
	pct_str(p) = string(round(100 * p; digits=1)) * "%"
	nothing
end

# ╔═╡ 81818181-8181-8181-8181-818181818181
md"""
## Player outcomes

**sole** = alone in first · **tied** = sole or shared first (site ranking) · score quantiles from the same draws.
"""

# ╔═╡ 82828282-8282-8282-8282-828282828282
with_terminal() do
	println("PLAYER OUTCOMES  (n=$(n_samples); openings Spidey=$(spidey_open) Odyssey=$(odyssey_open) PAW=$(paw_open) Mutiny=$(mutiny_open) Insidious=$(insidious_open))")
	println("-"^78)
	for i in sortperm(sim.win_shared; rev=true)
		println(
			rpad(sim.players[i], 10),
			" sole=", rpad(pct_str(sim.win_sole[i]), 6),
			" tied=", rpad(pct_str(sim.win_shared[i]), 6),
			" avg=", rpad(string(round(mean(sim.scores[i, :]); digits=1)), 5),
			" p10=", rpad(string(round(quantile(sim.scores[i, :], 0.1); digits=1)), 5),
			" p50=", rpad(string(round(quantile(sim.scores[i, :], 0.5); digits=1)), 5),
			" p90=", string(round(quantile(sim.scores[i, :], 0.9); digits=1)),
		)
	end
	println("-"^78)
	println(
		"sum sole=", round(sum(sim.win_sole); digits=3),
		"  sum tied=", round(sum(sim.win_shared); digits=3),
		"  P(Top10)>50%: ", count(sim.top10_prob .> 0.5),
		"  >5%: ", count(sim.top10_prob .> 0.05),
		"  ΣP(Top10)=", round(sum(sim.top10_prob); digits=2),
	)
end

# ╔═╡ 83000000-8300-8300-8300-830000000001
md"""
## Most representative Top 10 where each player wins

For every player with a non-zero chance of finishing sole **or tied** first: take all
posterior draws where they win, find the draw whose grosses sit closest to the median of
those wins (the **medoid**), and show that Top 10. Exact list-modes are nearly unique with
continuous grosses; this is the typical world in which they win.
"""

# ╔═╡ 83000000-8300-8300-8300-830000000002
with_terminal() do
	print_win_scenarios(sim)
end

# ╔═╡ 83838383-8383-8383-8383-838383838383
md"""
## Full Labor Day field ($(n_field) films)

Sorted by median season gross. Same layout as `scripts/sanity_review.jl`.
"""

# ╔═╡ 84848484-8484-8484-8484-848484848484
with_terminal() do
	println("FULL FIELD by median season G")
	println("-"^98)
	println(
		lpad("#", 2), "  ",
		rpad("Film", 40),
		" ", rpad("banked", 6),
		" ", rpad("med", 5),
		" ", rpad("[5%-95%]", 11),
		" ", rpad("Top10", 6),
		" ", " #1",
	)
	println("-"^98)
	for (rank, i) in enumerate(field_order)
		band = "[" * string(round(Int, lo[i] / 1e6)) * "-" * string(round(Int, hi[i] / 1e6)) * "]"
		println(
			lpad(string(rank), 2), ". ",
			rpad(sim.titles[i], 40),
			" ", rpad(m_str(banked[i]), 6),
			" ", rpad(m_str(med[i]), 5),
			" ", rpad(band, 11),
			" ", rpad(pct_str(sim.top10_prob[i]), 6),
			" ", rpad(pct_str(sim.rank_prob[i, 1]), 5),
		)
	end
end

# ╔═╡ 85858585-8585-8585-8585-858585858585
md"""
## High remaining (median / banked > 2×)

Early-in-run films can get aggressive geometric extrapolations — flag them.
"""

# ╔═╡ 86868686-8686-8686-8686-868686868686
with_terminal() do
	flags = Tuple{String,Float64,Float64,Float64,Float64,Float64}[]
	for (i, t) in enumerate(sim.titles)
		C = banked[i]
		C <= 0 && continue
		ratio = med[i] / C
		ratio > 2 || continue
		film = season.films[findfirst(f -> f.title == t, season.films)]
		push!(flags, (t, C, med[i], ratio, get(times, t, NaN), t_cutoff(film.release_date)))
	end
	if isempty(flags)
		println("None — no released film has median season total > 2× banked.")
	else
		println("HIGH REMAINING  (median G / banked > 2)")
		println("-"^90)
		for (t, C, M, ratio, tn, tc) in sort(flags; by = x -> -x[4])
			println(
				"  ", rpad(t, 40),
				" banked=", lpad(m_str(C), 5),
				" med=", lpad(m_str(M), 5),
				" x", round(ratio; digits=2),
				"  t_now=", round(tn; digits=1),
				"  t_cut=", round(tc; digits=1),
			)
		end
	end
end

# ╔═╡ 88888888-8888-8888-8888-888888888888
md"""
## Charts (secondary)

Heatmap + fan chart for the competitive slice; win bars for the six players.
"""

# ╔═╡ 99999999-9999-9999-9999-999999999999
begin
	by_top10 = findall(sim.top10_prob .> 0.01)
	by_median = field_order[1:min(20, n_field)]
	keep = sort(unique(vcat(by_top10, by_median)))
	hm_order = sortperm(med[keep]; rev=true)
	idx = keep[hm_order]
	labels = sim.titles[idx]
	fig = Figure(size=(900, max(420, 18 * length(idx))))
	ax = Axis(
		fig[1, 1];
		xlabel="Final rank",
		ylabel="Film",
		yticks=(1:length(idx), labels),
		xticks=1:10,
		title="P(finish at rank r) — $(length(idx)) of $(n_field) films",
	)
	heatmap!(ax, 1:10, 1:length(idx), sim.rank_prob[idx, :]')
	Colorbar(fig[1, 2], limits=(0, 1), label="probability")
	fig
end

# ╔═╡ bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
begin
	ord = field_order[1:min(20, n_field)]
	fig2 = Figure(size=(900, 520))
	ax2 = Axis(
		fig2[1, 1];
		xlabel="Film",
		ylabel="Season gross (\$M)",
		xticks=(1:length(ord), sim.titles[ord]),
		xticklabelrotation=0.7,
		title="Labor Day domestic gross — banked + remaining (top 20)",
	)
	for (j, i) in enumerate(ord)
		lines!(ax2, [j, j], [lo[i], hi[i]] ./ 1e6; color=:gray, linewidth=3)
		scatter!(ax2, [j], [med[i] / 1e6]; color=:dodgerblue, markersize=10)
	end
	fig2
end

# ╔═╡ eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee
begin
	fig4 = Figure(size=(700, 350))
	ax4 = Axis(fig4[1, 1]; xlabel="Player", ylabel="Probability", title="Win probability")
	x = 1:length(sim.players)
	barplot!(ax4, x .- 0.15, sim.win_sole; width=0.3, label="sole first", color=:steelblue)
	barplot!(ax4, x .+ 0.15, sim.win_shared; width=0.3, label="sole or tied first", color=:orange)
	ax4.xticks = (collect(x), sim.players)
	axislegend(ax4; position=:rt)
	fig4
end

# ╔═╡ 1e02c4e5-6f44-4d30-b398-470860dacebc


# ╔═╡ Cell order:
# ╟─11111111-1111-1111-1111-111111111111
# ╟─22222222-2222-2222-2222-222222222222
# ╟─33333333-3333-3333-3333-333333333333
# ╟─44444444-4444-4444-4444-444444444444
# ╟─55555555-5555-5555-5555-555555555555
# ╟─55555555-5555-5555-5555-555555555556
# ╟─55555555-5555-5555-5555-555555555557
# ╟─55555555-5555-5555-5555-555555555558
# ╟─55555555-5555-5555-5555-555555555559
# ╟─55555555-5555-5555-5555-55555555555a
# ╟─55555555-5555-5555-5555-55555555555b
# ╟─55555555-5555-5555-5555-55555555555c
# ╟─55555555-5555-5555-5555-55555555555d
# ╟─55555555-5555-5555-5555-55555555555e
# ╟─66666666-6666-6666-6666-666666666666
# ╟─77777777-7777-7777-7777-777777777777
# ╟─80808080-8080-8080-8080-808080808080
# ╟─81818181-8181-8181-8181-818181818181
# ╟─82828282-8282-8282-8282-828282828282
# ╟─83000000-8300-8300-8300-830000000001
# ╟─83000000-8300-8300-8300-830000000002
# ╟─83838383-8383-8383-8383-838383838383
# ╟─84848484-8484-8484-8484-848484848484
# ╟─85858585-8585-8585-8585-858585858585
# ╟─86868686-8686-8686-8686-868686868686
# ╟─88888888-8888-8888-8888-888888888888
# ╟─99999999-9999-9999-9999-999999999999
# ╟─bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
# ╟─eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee
# ╠═1e02c4e5-6f44-4d30-b398-470860dacebc
