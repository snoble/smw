#!/usr/bin/env julia
# Build static WASM site from notebooks/smw2026_wasm.jl via Snapshot.jl.
# Requires Julia 1.12 + Node with WasmGC (Homebrew node 25+ recommended).
#
#   ./scripts/install_julia_1_12.sh
#   nix-shell --run 'julia --project scripts/export_viewer_data.jl'
#   export PATH="/opt/homebrew/opt/node/bin:$PATH"   # Node 25 for WasmGC verify
#   .julia_versions/1.12.6/bin/julia --project=wasm scripts/build_wasm_site.jl
#   ./scripts/serve_wasm_site.sh

using Pkg
const ROOT = normpath(joinpath(@__DIR__, ".."))
Pkg.activate(joinpath(ROOT, "wasm"))
try
    Pkg.add("Snapshot")
catch
    Pkg.add(url = "https://github.com/GroupTherapyOrg/Snapshot.jl")
end
Pkg.instantiate()

using Snapshot

const NOTEBOOK = joinpath(ROOT, "notebooks", "smw2026_wasm.jl")
const SITE = joinpath(ROOT, "site")

isfile(NOTEBOOK) || error(
    "Missing $NOTEBOOK — run scripts/export_viewer_data.jl first",
)

# Prefer a Node that supports WasmGC (v22+ / Homebrew 25).
if isfile("/opt/homebrew/opt/node/bin/node")
    ENV["PATH"] = "/opt/homebrew/opt/node/bin:" * get(ENV, "PATH", "")
end
println("node: ", read(`node --version`, String))

mkpath(SITE)
println("Exporting ", NOTEBOOK, " → ", SITE)
html_path = export_notebook(NOTEBOOK; therapy = true, output_dir = SITE)
println("Wrote ", html_path)
println("Done. Serve with: ./scripts/serve_wasm_site.sh")
