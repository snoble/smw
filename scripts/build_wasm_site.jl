#!/usr/bin/env julia
# Compatibility entry point retained for the existing site workflow.
#
# The viewer is now purpose-built HTML/CSS/JS rather than Snapshot/WASM output.
# Run export_viewer_data.jl when model inputs change; this script validates that
# every static artifact required by GitHub Pages is present.

const ROOT = normpath(joinpath(@__DIR__, ".."))
const SITE = joinpath(ROOT, "site")
const REQUIRED = [
    "smw2026_wasm.html",
    "smw2026_viewer.css",
    "smw2026_charts.js",
    "smw_engine_worker.js",
    "smw2026_data.json",
]

missing = filter(name -> !isfile(joinpath(SITE, name)), REQUIRED)
isempty(missing) || error(
    "Missing static viewer artifacts: $(join(missing, ", ")). " *
    "Run `julia --project scripts/export_viewer_data.jl` first.",
)

println("Static Summer Movie Wager viewer is ready:")
for name in REQUIRED
    path = joinpath(SITE, name)
    println("  ", name, " (", filesize(path), " bytes)")
end
wasm = joinpath(SITE, "wasm", "smw_kernel.wasm")
if isfile(wasm)
    println("  wasm/smw_kernel.wasm (", filesize(wasm), " bytes)")
else
    println("  (optional) wasm/smw_kernel.wasm missing — worker will use js-fallback")
end
println("Serve with: ./scripts/serve_wasm_site.sh")
