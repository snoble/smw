using Test
using SMW
using Dates
using Distributions
using Random
using DataFrames
using Turing
using Statistics

const DATA = joinpath(@__DIR__, "..", "data")

include("test_scoring.jl")
include("test_data.jl")
include("test_model.jl")
include("test_simulate.jl")
include("test_integration.jl")
