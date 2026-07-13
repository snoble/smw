# Summer Movie Wager — Bayesian Outcome Visualizer

Interactive Julia project that models the **final Top 10 domestic box-office ranking**
of Summer 2026 as a probability distribution, then derives Summer Movie Wager scores
and win probabilities from it.

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
nix-shell --run 'julia -e "using Pkg; Pkg.add(\"Pluto\"); using Pluto; Pluto.run()"'
```

Then open [`notebooks/smw2026.jl`](notebooks/smw2026.jl).

## Smoke run (no Pluto)

```bash
nix-shell --run 'julia --project scripts/smoke.jl'
```

## Data files

| File | Role |
|---|---|
| `data/films_2026.csv` | Candidate universe (registry) |
| `data/weekly_2026.csv` | Cumulative gross observations over time |
| `data/picks_2026.csv` | Player Top 10 + dark horses |
| `data/historical/films_history.csv` | Training trajectories (synthetic placeholder for now) |
