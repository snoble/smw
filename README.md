# Summer Movie Wager — Bayesian Outcome Visualizer

Interactive Julia project that models the **final Top 10 domestic box-office ranking**
of Summer 2026 as a probability distribution, then derives Summer Movie Wager scores
and win probabilities from it.

**Live viewer:** [snoble.github.io/smw](https://snoble.github.io/smw/)

See [docs/brainstorms/2026-07-13-summer-movie-wager-bayesian-brainstorm.md](docs/brainstorms/2026-07-13-summer-movie-wager-bayesian-brainstorm.md)
for the design decisions.

## Setup

Requires [Nix](https://nixos.org/). From the repo root:

```bash
nix-shell
julia --project -e 'using Pkg; Pkg.instantiate()'
```

The first instantiate can take 10+ minutes (Turing + Makie precompile).

## Update weekly data

1. Edit [`data/weekly_2026.csv`](data/weekly_2026.csv) — add a new row per film with the
   latest cumulative domestic gross and date.
2. Optionally update [`data/films_2026.csv`](data/films_2026.csv) registry fields
   (`released`, notes, etc.).
3. Re-run the notebook (or `scripts/smoke.jl`); posterior draws cache to `output/`.

## Run tests

```bash
nix-shell --run 'julia --project -e "using Pkg; Pkg.test()"'
```

## Launch the notebook

Pluto cannot load a local package through its built-in package manager. The notebook
activates this project's environment on startup.

```bash
nix-shell --run 'julia --project -e "using Pluto; Pluto.run()"'
```

Then open [`notebooks/smw2026.jl`](notebooks/smw2026.jl).

If you see `UndefVarError: Slider not defined`, the notebook is using a stale buffer —
close the tab and reopen the file from disk (CairoMakie also exports `Slider`; we alias
PlutoUI's as `UISlider`).

## Smoke run (no Pluto)

```bash
nix-shell --run 'julia --project scripts/smoke.jl'
```

## Browser WASM viewer (experimental)

The full Turing notebook cannot run in WasmTarget. Instead:

1. **Offline (Julia 1.11 / nix-shell):** precompute posteriors → `notebooks/generated/viewer_data.jl`
2. **Lean notebook:** [`notebooks/smw2026_wasm.jl`](notebooks/smw2026_wasm.jl) switches Spider-Man opening scenarios in pure Julia
3. **Export (Julia 1.12 + Snapshot.jl):** compile `@bind` cells to WASM islands
4. **Serve locally** over HTTP

```bash
# 1) model data (nix-shell / Julia 1.11)
nix-shell --run 'julia --project scripts/export_viewer_data.jl'

# 2) Julia 1.12 for Snapshot / WasmTarget
chmod +x scripts/install_julia_1_12.sh scripts/serve_wasm_site.sh
./scripts/install_julia_1_12.sh

# 3) export static site (needs Node with WasmGC — Homebrew node 25+)
export PATH="/opt/homebrew/opt/node/bin:$PATH"
.julia_versions/1.12.6/bin/julia --project=wasm scripts/build_wasm_site.jl

# 4) open in browser
./scripts/serve_wasm_site.sh
# → http://127.0.0.1:8765/smw2026_wasm.html
```

Commit the regenerated `site/` directory; GitHub Actions deploys it to GitHub Pages on every push to `main`.

Season-total model: **already banked + positive remaining gross** (geometric decay pinned to the latest observation; sub-week pins floor at 1 week so early weak openers don't explode).

## Data files

| File | Role |
|---|---|
| `data/films_2026.csv` | Candidate universe (registry + optional `opening_prior_m` for unreleased) |
| `data/weekly_2026.csv` | Cumulative gross observations over time |
| `data/picks_2026.csv` | Player Top 10 + dark horses |
| `data/historical/films_history.csv` | Training trajectories (synthetic placeholder for now) |
| `notebooks/smw2026_wasm.jl` | WASM-friendly interactive viewer |
| `notebooks/generated/viewer_data.jl` | Precomputed scenarios (generated) |
