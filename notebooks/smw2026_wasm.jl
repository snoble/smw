### A Pluto.jl notebook ###
# v0.20.28

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

# ╔═╡ a0000000-0000-0000-0000-000000000002
begin
	using PlutoUI: Slider as UISlider
	const OPENINGS = Int[100, 150, 180, 220]
	const N_FILM = 33
	const TITLES = String[
    "The Devil Wears Prada 2",
    "Obsession",
    "Mortal Kombat II",
    "Star Wars: The Mandalorian and Grogu",
    "Backrooms",
    "Scary Movie",
    "Masters of the Universe",
    "Disclosure Day",
    "Toy Story 5",
    "Supergirl",
    "The Sheep Detectives",
    "Minions & Monsters",
    "Moana",
    "Cut Off",
    "The Odyssey",
    "Spider-Man: Brand New Day",
    "Ice Cream Man",
    "One Night Only",
    "Super Troopers 3",
    "The End of Oak Street",
    "PAW Patrol: The Dino Movie",
    "The Rivals of Amziah King",
    "Insidious: Out of the Further",
    "Mutiny",
    "Spa Weekend",
    "Cliffhanger",
    "Coyote vs. Acme",
    "The Dog Stars",
    "Finding Emily",
    "Fall 2: Deadpoint",
    "Evil Dead Burn",
    "Jackass: Best and Last",
    "Billie Eilish: Hit Me Hard and Soft"
]
	const BANKED_M = Int[220, 253, 80, 177, 194, 107, 64, 111, 404, 66, 66, 108, 43, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 18, 0, 10]
	const ORDER = Int[
    9 2 1 5 12 16 4 15 8 13 6 10 11 21 3 24 7 23 32 26 27 17 19 31 20 14 30 22 33 18 28 25 29
    9 16 2 1 12 5 4 15 8 13 6 11 10 3 21 24 7 23 26 32 27 17 19 31 20 30 14 22 33 18 28 25 29
    9 16 2 1 5 12 4 15 8 13 6 10 11 21 3 24 7 23 32 26 27 17 19 31 20 14 30 22 33 18 28 25 29
    9 16 2 1 5 12 4 15 8 13 6 10 11 21 3 24 7 23 32 26 27 17 19 31 20 14 30 22 33 18 28 25 29
]
	const MED_M = Int[
    222 258 82 182 205 117 69 127 509 100 99 203 123 15 148 183 26 9 23 17 82 12 41 77 6 34 28 6 4 14 19 36 10
    222 258 82 182 204 116 69 127 513 99 99 208 121 14 145 283 26 10 23 18 79 12 42 73 6 36 29 6 4 16 19 35 10
    222 258 82 182 205 117 69 127 509 100 99 203 123 15 148 329 26 9 23 17 82 12 41 77 6 34 28 6 4 14 19 36 10
    222 258 82 182 205 117 69 127 509 100 99 203 123 15 148 402 26 9 23 17 82 12 41 77 6 34 28 6 4 14 19 36 10
]
	const LO_M = Int[
    221 254 80 178 196 109 66 116 441 81 80 161 88 7 85 118 13 5 11 9 41 6 23 37 3 19 16 3 2 8 19 17 10
    221 254 80 178 196 109 65 116 442 82 81 153 89 8 85 186 14 4 11 9 37 6 23 37 3 17 16 3 2 8 19 19 10
    221 254 80 178 196 109 66 116 441 81 80 161 88 7 85 213 13 5 11 9 41 6 23 37 3 19 16 3 2 8 19 17 10
    221 254 80 178 196 109 66 116 441 81 80 161 88 7 85 260 13 5 11 9 41 6 23 37 3 19 16 3 2 8 19 17 10
]
	const HI_M = Int[
    231 277 89 196 228 133 78 151 618 135 134 260 172 31 272 291 52 18 43 33 149 24 84 142 10 62 52 12 7 31 19 77 12
    232 275 87 195 227 132 79 148 649 130 135 288 174 29 280 445 50 20 44 36 167 24 77 141 11 69 62 12 7 29 19 67 12
    231 277 89 196 228 133 78 151 618 135 134 260 172 31 272 524 52 18 43 33 149 24 84 142 10 62 52 12 7 31 19 77 12
    231 277 89 196 228 133 78 151 618 135 134 260 172 31 272 640 52 18 43 33 149 24 84 142 10 62 52 12 7 31 19 77 12
]
	const TOP10_T = Int[
    1000 1000 0 1000 1000 397 0 783 1000 163 140 1000 567 0 747 953 0 0 0 0 137 0 0 110 0 0 0 0 0 0 0 3 0
    1000 1000 0 1000 1000 403 0 823 1000 140 137 1000 507 0 743 1000 0 0 0 0 147 0 3 97 0 0 0 0 0 0 0 0 0
    1000 1000 0 1000 1000 377 0 783 1000 157 140 1000 557 0 743 1000 0 0 0 0 133 0 0 107 0 0 0 0 0 0 0 3 0
    1000 1000 0 1000 1000 377 0 783 1000 157 140 1000 557 0 743 1000 0 0 0 0 133 0 0 107 0 0 0 0 0 0 0 3 0
]
	const FIRST_T = Int[
    0 0 0 0 0 0 0 0 1000 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
    0 0 0 0 0 0 0 0 983 0 0 0 0 0 0 17 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
    0 0 0 0 0 0 0 0 943 0 0 0 0 0 0 57 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
    0 0 0 0 0 0 0 0 793 0 0 0 0 0 0 207 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
]
end

# ╔═╡ a0000000-0000-0000-0000-000000000001
md"""
# Summer Movie Wager 2026

Labor Day domestic box-office posterior for the **full 33-film field**, then wager
outcomes for all six players.

Season total = already banked + positive remaining. Spider-Man hasn't opened — the slider
is only a **sensitivity control** over four opening scenarios; released films stay pinned
to observed grosses.

Draws/scenario: 300. Cutoff: Sep 7.
"""

# ╔═╡ a0000000-0000-0000-0000-000000000003
md"""
## Spider-Man opening (sensitivity only)
**1**=\$100M · **2**=\$150M · **3**=\$180M · **4**=\$220M
"""

# ╔═╡ a0000000-0000-0000-0000-000000000004
@bind scen UISlider(1:4, default=3, show_value=true)

# ╔═╡ a0000000-0000-0000-0000-000000000005
opening_for(scen::Int64)::Int64 = OPENINGS[scen]

# ╔═╡ a0000000-0000-0000-0000-000000000006
opening_for(Int64(scen))

# ╔═╡ a0000000-0000-0000-0000-000000000007
md"""
## Player outcomes
**sole** = alone in first · **tied** = sole or shared first (how the site shows ranks) · **avg** = mean final score
"""

# ╔═╡ a0000000-0000-0000-0000-000000000008
function standings_for(scen::Int64)::String
    scen == 1 && return "Peter: sole 54.7%, tied 60.0%, avg 51.5 · BJ: sole 15.3%, tied 21.0%, avg 46.8 · Jeff: sole 14.0%, tied 16.3%, avg 46.3 · Germain: sole 4.3%, tied 6.7%, avg 44.9 · Devindra: sole 3.7%, tied 4.7%, avg 37.9 · David: sole 0.0%, tied 0.0%, avg 36.2"
    scen == 2 && return "Peter: sole 71.7%, tied 77.3%, avg 56.7 · BJ: sole 9.7%, tied 14.0%, avg 49.9 · Jeff: sole 10.3%, tied 12.7%, avg 50.4 · Germain: sole 2.0%, tied 2.3%, avg 46.1 · Devindra: sole 0.3%, tied 0.3%, avg 38.8 · David: sole 0.0%, tied 0.0%, avg 38.6"
    scen == 3 && return "Peter: sole 63.7%, tied 69.7%, avg 57.0 · Jeff: sole 14.0%, tied 16.0%, avg 52.2 · BJ: sole 8.7%, tied 14.7%, avg 51.0 · Germain: sole 4.0%, tied 4.3%, avg 47.2 · Devindra: sole 2.0%, tied 2.7%, avg 39.7 · David: sole 0.3%, tied 0.7%, avg 39.4"
    scen == 4 && return "Peter: sole 56.3%, tied 61.0%, avg 56.4 · Germain: sole 14.0%, tied 15.0%, avg 49.1 · Jeff: sole 12.0%, tied 13.3%, avg 51.7 · BJ: sole 6.3%, tied 10.7%, avg 50.4 · Devindra: sole 3.7%, tied 3.7%, avg 41.2 · David: sole 1.7%, tied 2.7%, avg 41.2"
    return ""
end

# ╔═╡ a0000000-0000-0000-0000-000000000009
standings_for(Int64(scen))

# ╔═╡ a0000000-0000-0000-0000-00000000000a
md"""
## Full predicted Labor Day field (33 films)
Pick a predicted rank (1 = highest median season gross). Shows banked, median band, P(Top 10), P(#1).
"""

# ╔═╡ a0000000-0000-0000-0000-00000000000b
@bind rank UISlider(1:33, default=1, show_value=true)

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
md"""
### Nearby ranks (same scenario)
"""

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
md"""
---
Local Pluto notebook (`notebooks/smw2026.jl`) has the full sortable table + charts.
"""

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"

[compat]
PlutoUI = "~0.7.83"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.12.6"
manifest_format = "2.0"
project_hash = "40c9f1cac973d64f8ca3ef3a09f769ff947e80f3"

[[deps.AbstractPlutoDingetjes]]
git-tree-sha1 = "6c3913f4e9bdf6ba3c08041a446fb1332716cbc2"
uuid = "6e696c72-6542-2067-7265-42206c756150"
version = "1.4.0"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.2"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"
version = "1.11.0"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"
version = "1.11.0"

[[deps.ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "67e11ee83a43eb71ddc950302c53bf33f0690dfe"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.12.1"
weakdeps = ["StyledStrings"]

    [deps.ColorTypes.extensions]
    StyledStringsExt = "StyledStrings"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "1.3.0+1"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"
version = "1.11.0"

[[deps.Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.7.0"

[[deps.FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"
version = "1.11.0"

[[deps.FixedPointNumbers]]
deps = ["Random", "Statistics"]
git-tree-sha1 = "59af96b98217c6ef4ae0dfe065ac7c20831d1a84"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.6"

[[deps.Hyperscript]]
deps = ["Test"]
git-tree-sha1 = "179267cfa5e712760cd43dcae385d7ea90cc25a4"
uuid = "47d2ed2b-36de-50cf-bf87-49c2cf4b8b91"
version = "0.0.5"

[[deps.HypertextLiteral]]
deps = ["Tricks"]
git-tree-sha1 = "d1a86724f81bcd184a38fd284ce183ec067d71a0"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "1.0.0"

[[deps.IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "0ee181ec08df7d7c911901ea38baf16f755114dc"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "1.0.0"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"
version = "1.11.0"

[[deps.JuliaSyntaxHighlighting]]
deps = ["StyledStrings"]
uuid = "ac6e5ff7-fb65-4e79-a425-ec3bc9c03011"
version = "1.12.0"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "0.6.4"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "OpenSSL_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "8.15.0+0"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "OpenSSL_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.11.3+1"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"
version = "1.11.0"

[[deps.LinearAlgebra]]
deps = ["Libdl", "OpenBLAS_jll", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
version = "1.12.0"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"
version = "1.11.0"

[[deps.MIMEs]]
git-tree-sha1 = "c64d943587f7187e751162b3b84445bbbd79f691"
uuid = "6c6e2e6c-3030-632d-7369-2d6c69616d65"
version = "1.1.0"

[[deps.Markdown]]
deps = ["Base64", "JuliaSyntaxHighlighting", "StyledStrings"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"
version = "1.11.0"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2025.11.4"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.3.0"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.29+0"

[[deps.OpenSSL_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "3.5.4+0"

[[deps.PlutoUI]]
deps = ["AbstractPlutoDingetjes", "Base64", "ColorTypes", "Dates", "Downloads", "FixedPointNumbers", "Hyperscript", "HypertextLiteral", "IOCapture", "InteractiveUtils", "Logging", "MIMEs", "Markdown", "Random", "Reexport", "URIs", "UUIDs"]
git-tree-sha1 = "e189d0623e7ce9c37389bac17e80aac3b0302e75"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.83"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"
version = "1.11.0"

[[deps.Random]]
deps = ["SHA"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"
version = "1.11.0"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"
version = "1.11.0"

[[deps.Statistics]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "ae3bb1eb3bba077cd276bc5cfc337cc65c3075c0"
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
version = "1.11.1"

    [deps.Statistics.extensions]
    SparseArraysExt = ["SparseArrays"]

    [deps.Statistics.weakdeps]
    SparseArrays = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.StyledStrings]]
uuid = "f489334b-da3d-4c2e-b8f0-e476e12c162b"
version = "1.11.0"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
version = "1.11.0"

[[deps.Tricks]]
git-tree-sha1 = "311349fd1c93a31f783f977a71e8b062a57d4101"
uuid = "410a4b4d-49e4-4fbc-ab6d-cb71b17b3775"
version = "0.1.13"

[[deps.URIs]]
git-tree-sha1 = "bef26fb046d031353ef97a82e3fdb6afe7f21b1a"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.6.1"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"
version = "1.11.0"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"
version = "1.11.0"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.3.1+2"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.15.0+0"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.64.0+1"
"""

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
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
