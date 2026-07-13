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
const REPORTS = joinpath(SITE, "smw2026_reports.json")

isfile(NOTEBOOK) || error(
    "Missing $NOTEBOOK — run scripts/export_viewer_data.jl first",
)
isfile(REPORTS) || error(
    "Missing $REPORTS — run scripts/export_viewer_data.jl first",
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

function polish_html!(html_path::AbstractString, reports_path::AbstractString)
    html = read(html_path, String)

    # Turn "@smw:…" sentinel string cells into empty <pre> hosts for JS.
    # Only rewrite pluto-output nodes — never the hidden pl-code source.
    sentinels = Dict(
        "@smw:players" => "smw-players",
        "@smw:wins" => "smw-wins",
        "@smw:heat" => "smw-heat",
        "@smw:field" => "smw-field",
    )
    for (token, id) in sentinels
        quoted = "\"$(token)\""
        repl = """<pluto-output class="rich_output smw-report" data-smw="$(id)"><pre class="smw-pre" id="$(id)">Loading…</pre></pluto-output>"""
        html = replace(
            html,
            Regex("""<pluto-output class="rich_output" id="[^"]+">\\Q$(quoted)\\E</pluto-output>""") =>
                repl,
        )
    end

    # Unquote the SCEN=… openings label for cleaner display
    html = replace(
        html,
        r"""(<pluto-output class="rich_output" id="[^"]+)">"SCEN=([^"]+)"</pluto-output>""" =>
            s"""\1 smw-scen">SCEN=\2</pluto-output>""",
    )

    polish = """
<style id="smw-polish">
.pl-code { display: none !important; }
pre.smw-pre, pluto-output.smw-report {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace !important;
  font-size: 0.78rem !important;
  white-space: pre !important;
  line-height: 1.35 !important;
  overflow-x: auto;
  margin: 0;
  background: transparent;
  border: none;
  padding: 0.35rem 0 0.75rem;
}
pluto-output .markdown {
  font-family: var(--system-ui-font-stack, ui-sans-serif, system-ui, sans-serif) !important;
  font-size: 1rem !important;
  white-space: normal !important;
  line-height: 1.65 !important;
}
body { max-width: 1040px !important; }
bond input[type=range] { width: min(22rem, 100%); }
</style>
<script id="smw-reports">
(function () {
  var reports = null;
  var lastScen = null;
  function currentScen(fallback) {
    var nodes = document.querySelectorAll('pluto-output.rich_output');
    for (var i = 0; i < nodes.length; i++) {
      var t = nodes[i].textContent || '';
      var m = t.match(/SCEN=(\\d+)/);
      if (m) return parseInt(m[1], 10);
    }
    return fallback || 40;
  }
  function apply(scen) {
    if (!reports) return;
    var idx = scen - 1;
    if (idx < 0 || idx >= reports.players.length) return;
    if (scen === lastScen) return;
    lastScen = scen;
    var map = {
      'smw-players': reports.players[idx],
      'smw-wins': reports.wins[idx],
      'smw-heat': reports.heat[idx],
      'smw-field': reports.field[idx]
    };
    Object.keys(map).forEach(function (id) {
      var el = document.getElementById(id);
      if (el) el.textContent = map[id];
    });
  }
  function tick() {
    apply(currentScen(reports && reports.default));
  }
  fetch('smw2026_reports.json')
    .then(function (r) { return r.json(); })
    .then(function (data) {
      reports = data;
      tick();
      var obs = new MutationObserver(tick);
      obs.observe(document.body, { childList: true, subtree: true, characterData: true });
      setInterval(tick, 400);
    })
    .catch(function (err) {
      console.error('SMW reports failed to load', err);
    });
})();
</script>
"""
    if !occursin("smw-polish", html)
        html = replace(html, "</head>" => polish * "</head>"; count = 1)
    end
    write(html_path, html)
    println("Polished ", html_path)
end

polish_html!(html_path, REPORTS)
println("Done. Serve with: ./scripts/serve_wasm_site.sh")
