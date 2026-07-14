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
include("inference.jl")

export SEASON_START, SEASON_CUTOFF
export Film, Observation, PlayerPicks, SeasonData
export load_films, load_weekly, load_picks, load_historical, load_season
export fallback_observations, interval_observations
export run_weeks, observation_run_weeks, t_cutoff, rank_by_gross
export score_pick, score_list, standings, shared_ranks
export cumulative_gross, season_total, fit_type_priors, sample_posterior, season_gross_draws
export prior_predictive_grosses, build_array_model, observed_floors, observed_times
export unreleased_prior
export SimulationResult, simulate_outcomes, print_win_scenarios
export curve_factor, interval_factor, remaining_factor, logistic, logit
export logO_posterior, hermite_nodes, legendre_nodes
export theater_tail_observation, FilmPrior, InferenceConfig, DEFAULT_INFERENCE
export film_eta_posterior, sigma_posterior, sample_factored_grosses
export rank_list_distance, representative_win_draw
export film_priors_from_season

end # module
