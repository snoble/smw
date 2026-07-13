module SMW

using CSV
using DataFrames
using Dates
using Distributions
using Random
using StatsBase
using Turing

include("data.jl")
include("scoring.jl")
include("model.jl")
include("simulate.jl")

export SEASON_START, SEASON_CUTOFF
export Film, Observation, PlayerPicks, SeasonData
export load_films, load_weekly, load_picks, load_historical, load_season
export run_weeks, t_cutoff, rank_by_gross
export score_pick, score_list, standings, shared_ranks
export cumulative_gross, fit_type_priors, sample_posterior, season_gross_draws
export prior_predictive_grosses, build_array_model
export SimulationResult, simulate_outcomes

end # module
