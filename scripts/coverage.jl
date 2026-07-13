#!/usr/bin/env julia
# Run the test suite with coverage and print a per-file report.
# Usage (from repo root, inside nix-shell):
#   julia --project scripts/coverage.jl

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
Pkg.test("SMW"; coverage = true)

using Coverage

const ROOT = normpath(joinpath(@__DIR__, ".."))
const SRC = joinpath(ROOT, "src")

function summarize(coverage, root)
    total_hit = 0
    total_miss = 0
    println()
    println("="^60)
    println("SMW coverage")
    println("="^60)
    for f in sort(coverage; by = x -> x.filename)
        hit = count(x -> x !== nothing && x > 0, f.coverage)
        miss_lines = findall(x -> x !== nothing && x == 0, f.coverage)
        miss = length(miss_lines)
        lines = hit + miss
        total_hit += hit
        total_miss += miss
        pct = lines == 0 ? 100.0 : round(100 * hit / lines; digits = 1)
        rel = replace(f.filename, root * "/" => "")
        println(rpad(rel, 28), " ", lpad(string(hit), 4), "/", lines, "  (", pct, "%)")
        if !isempty(miss_lines)
            src_lines = readlines(f.filename)
            for ln in miss_lines
                println("    miss ", ln, ": ", strip(get(src_lines, ln, "")))
            end
        end
    end
    total = total_hit + total_miss
    pct = total == 0 ? 100.0 : round(100 * total_hit / total; digits = 1)
    println("-"^60)
    println(rpad("TOTAL", 28), " ", lpad(string(total_hit), 4), "/", total, "  (", pct, "%)")
    println("="^60)
    return pct
end

coverage = process_folder(SRC)
pct = summarize(coverage, ROOT)
LCOV.writefile(joinpath(ROOT, "lcov.info"), coverage)
println("Wrote lcov.info")
pct >= 95.0 || error("coverage $pct% is below the 95% bar")
println("OK: coverage ≥ 95%")
