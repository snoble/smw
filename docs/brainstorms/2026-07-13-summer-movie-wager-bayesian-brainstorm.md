---
date: 2026-07-13
topic: summer-movie-wager-bayesian
---

# Summer Movie Wager — Bayesian Outcome Visualizer (Julia)

## What We're Building

An interactive **Pluto.jl** notebook that models the **final Top 10 domestic box-office
ranking** of Summer 2026 as a probability distribution, and derives the Summer Movie Wager
outcomes (player scores + win probabilities) from it.

The core random object is the **final ranked list**. Given (a) partial 2026 box-office data —
some films finished, some mid-run, some unopened — and (b) box-office dynamics learned from
past summers, we produce a **joint posterior predictive distribution over every film's
domestic gross as of the season cutoff (Labor Day, Sep 7)**, sample it many times, rank each
sample, and read off:

- Per-film probability of finishing in each rank / making the Top 10.
- Each player's final-score distribution (via the wager's scoring rules).
- Each player's probability of winning.

## Why This Approach

Considered three engines:

- **Pure Monte-Carlo with hand-fit decay curves** — simple, but throws away principled
  uncertainty and can't pool information across films.
- **Full Turing.jl hierarchical model** — principled posteriors, partial pooling.
- **Hybrid (chosen): Turing.jl for the gross model + Monte-Carlo for the downstream wager.**

Chosen the hybrid because the quantities of interest (ranks, win odds) are **nonlinear
functions of grosses**, so we must sample regardless. A hierarchical Turing model gives us the
right samples to push through: a **mid-run film is pinned down by its own trajectory**, while
an **unopened film gracefully falls back to the population prior** with appropriately wide
uncertainty. Downstream, ranking + scoring is a deterministic function applied per posterior
draw.

## The Domain (reference)

**Game:** 6 players (Jeff, Devindra, Germain, Peter, David, BJ) each submit a ranked Top 10 +
3 dark horses. Season: Apr 30 → Labor Day (Sep 7) 2026.

**Scoring per pick (single highest applicable rule):**

| Condition | Points |
|---|---|
| Correct #1 or #10 | 13 |
| Correct #2–#9 | 10 |
| 1 spot off | 7 |
| 2 spots off | 5 |
| Anywhere else in Top 10 | 3 |
| Missed Top 10 | 0 |
| Dark horse lands in Top 10 | 1 (additive across dark horses) |

**Current standings (07/13/2026, provisional):** Jeff 46, Devindra 39, Germain 39, Peter 38,
David 36, BJ 33. Not final — big unopened films remain (The Odyssey 7/17, Spider-Man: Brand
New Day 7/31, PAW Patrol 8/14, tail through 9/2), and mid-run films are still climbing.

## Key Decisions

- **Primary object = the final Top 10 list.** Wager scores/win-odds are derived readouts, not
  the model's core. Rationale: the list is the more interesting/general object.
- **Target variable = gross through Labor Day (Sep 7), not lifetime gross.** The wager is
  settled on the season window, which matters enormously for late releases: Cliffhanger and
  Coyote vs. Acme open Aug 28 (~10 days of runway), Fall 2: Deadpoint opens Sep 2 (~5 days).
  The run curve is evaluated at the truncation date, and historical training data must record
  where in the season each film opened. (Verify the exact cutoff rule against the site during
  planning.)
- **Candidate universe = players' picks ∪ all wide releases in the window, updated with news
  learned since picks were made.** The Top 10 is drawn from the whole field, not just picked
  films — and this is already biting: Backrooms sits at #4 on nobody's list, and The Sheep
  Detectives (#11) trails Supergirl (#10) by ~$20K. Seed the universe from the picks, add
  every wide release on the site's Upcoming Releases calendar, and fold in post-pick news
  (surprise hits, release-date moves, films pulled from the schedule). Optionally include a
  small "unknown breakout" allowance for films not yet on the radar.
- **Deliverable = Pluto.jl notebook.** Reactive sliders to explore assumptions live.
- **Engine = hybrid Turing.jl hierarchical gross model + Monte-Carlo ranking/scoring.**
- **Train on past summers.** Learn decay-curve shape and opening→final multipliers from
  historical films (site archives: 2007–2019 and 2022–2025; no 2020–2021) + Box Office Mojo
  weekly trajectories. Exclude the pandemic gap and treat 2022 (recovery year) with caution —
  flag it and check whether including it degrades the historical fit.
- **Validate by backtesting a past summer.** Before trusting 2026 output, hold out a completed
  season (e.g. 2024), feed the model only data through mid-July, and check that the actual
  final list falls inside the predicted distribution (rank coverage, calibration of credible
  intervals). This is a first-class step, not an afterthought.
- **Design for a weekly update loop.** Opening weekend is the single most informative datum
  for an unreleased film, and The Odyssey opens within days. The notebook is built around
  "drop new weekly numbers into the CSV → re-run" so posteriors sharpen as the season plays
  out.
- **Unreleased-film handling = hierarchical prior + optional manual overrides.** Pluto sliders
  let us inject domain knowledge (e.g. "Spider-Man final ≈ $X" or an expected opening) that
  updates the prior for that film; default is the pooled prior from comps.
- **Data source = curated CSV snapshot first, scraper later.** De-risks the modeling work;
  assemble a clean dataset now, automate ingestion once the model proves out.

## Proposed Model Sketch (for the planning phase)

- Model cumulative domestic gross for film *i* at week *t* of its run as a parametric run
  curve (e.g. saturating growth toward a lifetime total `F_i` with a decay rate), so
  `gross_i(t) = F_i · S(t; θ_i)` where `S` is a normalized accumulation curve in [0,1].
- **The wager quantity is the truncated gross** `G_i = gross_i(t_cutoff(i))`, where
  `t_cutoff(i)` is the number of run-weeks film *i* gets before Labor Day. For early-summer
  films `G_i ≈ F_i`; for late-August films the truncation dominates and `G_i ≪ F_i`.
- **Hierarchical priors:** curve-shape params `θ_i` and the opening→final relationship drawn
  from population distributions fit on historical films (optionally grouped by film type:
  franchise/animation/horror/etc.).
- **Likelihood:** observed weekly/cumulative grosses for released 2026 films constrain `F_i`
  and `θ_i`. Unreleased films have no likelihood term → posterior = prior (+ any override).
- **Posterior predictive → simulate:** draw `{G_i}` jointly over the full candidate universe,
  rank, compute wager scores, tally wins. Aggregate over draws for all target visualizations.

## Target Visualizations (derive-from-the-list)

- Per-film **rank probability heatmap** (film × rank, shaded by probability).
- **Season-gross fan chart** per film — gross through Labor Day, median + credible bands,
  released vs projected.
- Player **score distributions** (ridgeline/violin) + **win-probability bar chart**.
- "What needs to happen" view: conditional win-odds given a slider assumption.

## Open Questions (for planning)

- Curve family: single saturating curve vs. two-phase (opening bump + decay) — decide during
  fitting on historical data.
- Grouping for the hierarchy: by genre/type, by release timing, or fully pooled? Start simple
  (fully pooled), add grouping if it improves historical fit.
- Correlated shocks (e.g. a strong weekend lifts all films, two family films cannibalizing
  each other)? Likely v2; start with conditional independence given hierarchical params.
- Exact historical coverage available from Box Office Mojo weekly data — verify during data
  assembly.
- Exact season-cutoff rule: confirm whether the site counts gross strictly through Labor Day
  or uses another convention (e.g. the last reporting weekend).
- Tie rules, both layers: (a) near-ties in film gross at the #10 boundary are a 3-vs-0-point
  cliff (Supergirl vs. The Sheep Detectives are ~$20K apart today) — sampling handles this
  naturally, but the scoring function needs a deterministic tie-break for exactly-equal draws;
  (b) player-score ties — the site shares ranks (Devindra/Germain both shown 2nd at 39), so
  define "win probability" as P(sole or shared first) or report both.
- How to parameterize the "unknown breakout" allowance, if included at all.

## Next Steps

→ `/workflows:plan` for implementation details: project scaffolding (Project.toml, Turing,
Pluto, Makie/AlgebraOfGraphics), data schema for the curated CSV, historical-fit module,
scoring module, and the notebook layout.
