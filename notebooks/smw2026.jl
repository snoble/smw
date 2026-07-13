### A Pluto.jl notebook ###
# v0.20.4

using Markdown
using InteractiveUtils

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
	using PlutoUI
	using Statistics
	using Dates
	using Serialization
end

# ╔═╡ 22222222-2222-2222-2222-222222222222
md"""
# Summer Movie Wager 2026 — Bayesian outcomes

Posterior over each film's **Labor Day (Sep 7) domestic gross**, ranked into a Top 10,
then scored with the wager rules.

Update `data/weekly_2026.csv`, then re-run. Cached posteriors live in `output/`.
"""

# ╔═╡ 33333333-3333-3333-3333-333333333333
md"""
## Controls
"""

# ╔═╡ 44444444-4444-4444-4444-444444444444
@bind n_samples Slider(100:100:800, default=300, show_value=true)

# ╔═╡ 55555555-5555-5555-5555-555555555555
@bind spidey_open Slider(50:10:250, default=150, show_value=true)

# ╔═╡ 66666666-6666-6666-6666-666666666666
md"""
Spider-Man expected opening (\$M): **$(spidey_open)** · NUTS samples: **$(n_samples)**
"""

# ╔═╡ 77777777-7777-7777-7777-777777777777
begin
	season = load_season(joinpath(root, "data"))
	overrides = Dict{String,NamedTuple}(
		"Spider-Man: Brand New Day" => (
			logO_mean = log(Float64(spidey_open) * 1_000_000),
			logO_std = 0.35,
		),
	)
	mkpath(joinpath(root, "output"))
	cache_key = joinpath(root, "output", "posterior_s$(n_samples)_sp$(spidey_open).jls")
	if isfile(cache_key)
		posterior = open(deserialize, cache_key, "r")
	else
		posterior = sample_posterior(season; overrides, n_samples=Int(n_samples), progress=true)
		open(io -> serialize(io, posterior), cache_key, "w")
	end
	sim = simulate_outcomes(season, posterior)
	nothing
end

# ╔═╡ 88888888-8888-8888-8888-888888888888
md"""
## Rank probability heatmap
"""

# ╔═╡ 99999999-9999-9999-9999-999999999999
begin
	keep = findall(sim.top10_prob .> 0.02)
	order = sortperm(sim.top10_prob[keep]; rev=true)
	idx = keep[order]
	labels = sim.titles[idx]
	fig = Figure(size=(900, max(400, 22 * length(idx))))
	ax = Axis(
		fig[1, 1];
		xlabel="Final rank",
		ylabel="Film",
		yticks=(1:length(idx), labels),
		xticks=1:10,
		title="P(film finishes at rank r)",
	)
	heatmap!(ax, 1:10, 1:length(idx), sim.rank_prob[idx, :]')
	Colorbar(fig[1, 2], limits=(0, 1), label="probability")
	fig
end

# ╔═╡ aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
md"""
## Season-gross fan chart (median + 90% band)
"""

# ╔═╡ bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
begin
	G = sim.G
	med = vec(mapslices(median, G; dims=2))
	lo = vec(mapslices(x -> quantile(x, 0.05), G; dims=2))
	hi = vec(mapslices(x -> quantile(x, 0.95), G; dims=2))
	ord = sortperm(med; rev=true)[1:min(15, length(med))]
	fig2 = Figure(size=(900, 500))
	ax2 = Axis(
		fig2[1, 1];
		xlabel="Film",
		ylabel="Season gross (\$M)",
		xticks=(1:length(ord), sim.titles[ord]),
		xticklabelrotation=0.6,
		title="Labor Day domestic gross — posterior",
	)
	for (j, i) in enumerate(ord)
		lines!(ax2, [j, j], [lo[i], hi[i]] ./ 1e6; color=:gray, linewidth=3)
		scatter!(ax2, [j], [med[i] / 1e6]; color=:dodgerblue, markersize=10)
	end
	fig2
end

# ╔═╡ cccccccc-cccc-cccc-cccc-cccccccccccc
md"""
## Player score distributions & win probabilities
"""

# ╔═╡ dddddddd-dddd-dddd-dddd-dddddddddddd
begin
	fig3 = Figure(size=(900, 400))
	ax3 = Axis(fig3[1, 1]; xlabel="Final score", ylabel="Player", title="Score posterior")
	for (i, player) in enumerate(sim.players)
		ys = fill(Float64(i), size(sim.scores, 2))
		scatter!(ax3, sim.scores[i, :], ys .+ 0.05 .* randn(size(sim.scores, 2)); markersize=3, color=(:black, 0.15))
		dens = [quantile(sim.scores[i, :], q) for q in (0.1, 0.5, 0.9)]
		lines!(ax3, dens, fill(Float64(i), 3); color=:crimson, linewidth=2)
	end
	ax3.yticks = (1:length(sim.players), sim.players)
	fig3
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

# ╔═╡ ffffffff-ffff-ffff-ffff-ffffffffffff
md"""
## What needs to happen

Condition on Spider-Man's opening via the slider, then read win odds below.
"""

# ╔═╡ 10101010-1010-1010-1010-101010101010
Text(join(["$(p): $(round(100 * w; digits=1))%" for (p, w) in zip(sim.players, sim.win_sole)], " · "))

# ╔═╡ Cell order:
# ╠═11111111-1111-1111-1111-111111111111
# ╟─22222222-2222-2222-2222-222222222222
# ╟─33333333-3333-3333-3333-333333333333
# ╠═44444444-4444-4444-4444-444444444444
# ╠═55555555-5555-5555-5555-555555555555
# ╟─66666666-6666-6666-6666-666666666666
# ╠═77777777-7777-7777-7777-777777777777
# ╟─88888888-8888-8888-8888-888888888888
# ╠═99999999-9999-9999-9999-999999999999
# ╟─aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
# ╠═bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
# ╟─cccccccc-cccc-cccc-cccc-cccccccccccc
# ╠═dddddddd-dddd-dddd-dddd-dddddddddddd
# ╠═eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee
# ╟─ffffffff-ffff-ffff-ffff-ffffffffffff
# ╠═10101010-1010-1010-1010-101010101010
