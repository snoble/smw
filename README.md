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

With line coverage (writes `lcov.info`, fails below 95%):

```bash
nix-shell --run 'julia --project scripts/coverage.jl'
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

## Static browser viewer

The viewer conditions the full 2026 slate **in-browser**: fitted historical type priors and
raw interval observations are shipped as a versioned input bundle (no posterior draws).
A Web Worker runs nested quadrature + progressive Monte Carlo (1k preview → 20k final).
A Julia/WasmTarget numeric kernel is compiled for the same ABI (`site/wasm/smw_kernel.wasm`);
the worker currently uses a JS fallback for draws and reports `wasm binary present` when the
module loads.

Design notes: [docs/brainstorms/2026-07-13-julia-wasm-bayesian-engine-brainstorm.md](docs/brainstorms/2026-07-13-julia-wasm-bayesian-engine-brainstorm.md).

```bash
# Regenerate site/smw2026_data.json after model or data changes (no NUTS)
nix-shell --run 'julia --project scripts/export_viewer_data.jl'

# Recompile the WasmTarget kernel (Julia 1.12 local toolchain)
.julia_versions/1.12.6/bin/julia --project=wasm scripts/wasm_spike.jl

# Open in a browser
./scripts/serve_wasm_site.sh
# → http://127.0.0.1:8765/smw2026_wasm.html
```

Commit the regenerated `site/` directory; GitHub Actions deploys it to GitHub Pages on every push to `main`.

Season-total model: **already banked + positive remaining gross** (geometric decay pinned to the latest observation; theater-tail soft constraint near end of run).

## Data files

| File | Role |
|---|---|
| `data/films_2026.csv` | Candidate universe (registry + optional `opening_prior_m` for unreleased) |
| `data/weekly_2026.csv` | Cumulative gross + theaters + source over time |
| `data/exclusions_2026.csv` | Pre-window titles excluded from the wager |
| `data/picks_2026.csv` | Player Top 10 + dark horses |
| `data/historical/films_history.csv` | Training trajectories (synthetic placeholder for now) |
| `site/smw2026_wasm.html` | Fully-static interactive viewer |
| `site/smw2026_data.json` | Versioned input bundle: priors, intervals, picks (generated) |
| `site/smw_engine_worker.js` | Progressive inference Web Worker |
| `site/wasm/smw_kernel.wasm` | WasmTarget-compiled numeric kernel |
