#!/usr/bin/env julia
# Feasibility spike: compile SMWKernel with WasmTarget Vector bridge + Node worker.
#
#   .julia_versions/1.12.6/bin/julia --project=wasm scripts/wasm_spike.jl

using WasmTarget

const ROOT = normpath(joinpath(@__DIR__, ".."))
include(joinpath(ROOT, "src", "wasm_kernel.jl"))
using .SMWKernel

const OUT_DIR = joinpath(ROOT, "site", "wasm")
const WASM_PATH = joinpath(OUT_DIR, "smw_kernel.wasm")
mkpath(OUT_DIR)

# Manual Vector{Float64} bridge (WasmTarget does not auto-export these).
bv_new(n::Int64)::Vector{Float64} = Vector{Float64}(undef, Int(n))
bv_set!(v::Vector{Float64}, i::Int64, val::Float64)::Int64 = (v[Int(i)] = val; Int64(0))
bv_get(v::Vector{Float64}, i::Int64)::Float64 = v[Int(i)]
bv_len(v::Vector{Float64})::Int64 = Int64(length(v))

println("Compiling kernel + Vector bridge …")
bytes = compile_multi([
    (spike_kernel!, (Vector{Float64}, Vector{Float64})),
    (run_simulation!, (Vector{Float64}, Vector{Float64})),
    (bv_new, (Int64,)),
    (bv_set!, (Vector{Float64}, Int64, Float64)),
    (bv_get, (Vector{Float64}, Int64)),
    (bv_len, (Vector{Float64},)),
])
write(WASM_PATH, bytes)
cp(WASM_PATH, joinpath(OUT_DIR, "smw_spike.wasm"); force = true)
println("Wrote ", WASM_PATH, " (", length(bytes), " bytes)")

println("Running Node worker smoke test …")
run(`node $(joinpath(OUT_DIR, "smw_spike_run.mjs"))`)
println("WASM spike OK")
