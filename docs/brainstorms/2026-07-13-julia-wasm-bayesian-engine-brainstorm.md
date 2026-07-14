---
date: 2026-07-13
topic: julia-wasm-bayesian-engine
---

# Julia WASM Bayesian Engine

## What We're Building

A fully **client-side Julia/WasmTarget** inference engine that conditions the 2026 Summer
Movie Wager model in-browser. It loads **fitted historical type priors** and **raw 2026
observations** (no posterior draws), numerically integrates each film's posterior, then runs
**progressive Monte Carlo** for rankings, scores, and winners.

The browser never ships MCMC draws. Fitted EB priors are inputs; the engine produces the full
2026 posterior predictive over Labor Day grosses, then pushes samples through ranking +
scoring.

## Why This Approach

Approaches considered:

1. **Nested Gauss–Hermite / Legendre quadrature with analytic logO integration** (chosen)
2. Adaptive per-film posterior grids
3. Sequential importance resampling
4. Full NUTS in browser / Stan WASM — rejected; unnecessary for this structure

Chosen because films **factorize once σ_obs is handled**; **logO is conditionally conjugate
given decay**; only ranks and scores need Monte Carlo. Quadrature + exact conditional
sampling keeps the WASM footprint small and the math exact where it matters.

## Key Decisions

- **Fitted historical priors are fixed EB inputs.** “Full posterior” means the full 2026
  posterior **conditional on those priors**, not a joint re-fit of history + 2026.
- **Observation model = non-overlapping gross increments**, not independent nested
  cumulatives (avoids double-counting correlated weekly totals).
- **Shared σ_obs** marginalized with Gauss–Legendre on truncated Normal(0.15, 0.1) on
  `[0.02, 1]`.
- **Decay η = logit(d)** marginalized with Gauss–Hermite. For fixed `(η, σ)`, integrate
  **logO analytically** and sample from the exact conditional Gaussian.
- **Theater-tail constraint:** remaining gross expressed conjugately as
  `logO + log(tail_factor)` with calibrated uncertainty from exhibition state (theaters,
  PTA) — a soft conjugate update, not a hard cap.
- **Progressive simulation:** 1k preview, then 20k refinement, with **common random
  numbers** so the refinement continues the same stream.
- **Representative winning world:** the actual winning draw nearest the consensus ranking
  under **rank distance** (not a dollar-space medoid).
- **Engine = Julia/WasmTarget first.** Rust only if profiling proves a bottleneck; no
  silent replacement of the Julia path.
- **Data corrections for this spike:** Sheep Detectives May 8 release + 160 theaters
  terminal state; audit `eligible` field; exclude pre-window Michael / Mario / Hail Mary.

## Inference Sketch

For each film with observations (or a theater-tail prior):

1. Outer: Gauss–Legendre over σ_obs on the truncated Normal prior.
2. Inner: Gauss–Hermite over η = logit(d).
3. At each node: closed-form Gaussian posterior for logO; sample logO | η, σ exactly.
4. Map `(logO, η)` → Labor Day gross (and remaining tail if still in theaters).
5. Unreleased films: draw from type prior only (no likelihood).

Aggregate film grosses → rank → score wager → tally wins. Progressive MC upgrades from
preview to refinement without restarting RNG.

## Open Questions

- Exact quadrature orders for release — start **32×32**; treat as converged if bumping
  order changes probabilities by ≤ **0.25 pp**.
- ~~WASM bundle size / **WasmTarget feasibility** spike outcome.~~
  **Resolved (2026-07-13):** spike compiles `spike_kernel!` + `run_simulation!` with a
  manual `Vector{Float64}` bridge (`bv_new`/`bv_set!`/`bv_get`/`bv_len`) to ~172 KB and
  runs inside a Node Worker. Seeded Box–Muller `randn`, `exp`/`log`, and sorting of 33
  films all work. Do not silently replace Julia with Rust.
- Whether shipped priors are **real historical fits** vs the current synthetic provisional
  label.

## Next Steps

→ Implementation plan: **Julia WASM Bayesian Engine** (WasmTarget spike, quadrature
orders, data audit, progressive MC + rank-distance winning world, browser glue).
