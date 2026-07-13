# Historical training data

`films_history.csv` is the training set for the hierarchical box-office run-curve
model. Each row is one film at one week of its domestic run:

| column | meaning |
|---|---|
| `year` | summer season |
| `title` | film title |
| `type` | genre/type bucket for hierarchical pooling (animation, superhero, horror, drama, franchise, comedy, family, scifi) |
| `week` | weeks since wide release (1 = opening week) |
| `cumulative_gross` | cumulative domestic gross at end of that week (USD) |
| `final_gross` | the film's final domestic gross (USD) |

## Status: SYNTHETIC PLACEHOLDER

The current rows are **synthetic** — generated from saturating run curves
(`final * (1 - exp(-week/tau))`) with different `tau` per type — purely so the
modeling pipeline runs end to end. **Replace with real data before trusting any
output.**

## Populating real data

Source weekly domestic cumulative grosses from Box Office Mojo (linked per film on
thesummermoviewager.com) for past summers (site archives go back to 2007). A future
`scripts/scrape_bom.jl` will automate this; until then, append real rows in the
schema above and delete the synthetic ones.
