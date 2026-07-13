# Reproducible dev shell for the Summer Movie Wager Bayesian project.
#
#   nix-shell            # drops you into a shell with Julia + tooling
#   nix-shell --run ...  # run a single command inside the environment
#
# nixpkgs is pinned to the 25.05 release tarball so everyone gets the same
# Julia. Bump the URL + sha256 to update.
let
  nixpkgs = fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/refs/tags/25.05.tar.gz";
    sha256 = "1915r28xc4znrh2vf4rrjnxldw2imysz819gzhk9qlrkqanmfsxd";
  };
  pkgs = import nixpkgs { };
in
pkgs.mkShell {
  name = "smw";

  buildInputs = [
    pkgs.julia_111-bin # Julia 1.11 (prebuilt binary)
    pkgs.git
  ];

  # Keep the Julia depot inside the project so the nix store stays clean and
  # the environment is self-contained / easy to blow away.
  shellHook = ''
    export JULIA_DEPOT_PATH="$PWD/.julia_depot"
    export JULIA_PROJECT="$PWD"
    echo "smw dev shell — julia $(julia --version | awk '{print $3}')"
    echo "  JULIA_PROJECT=$JULIA_PROJECT"
    echo "  run: julia --project -e 'using Pkg; Pkg.instantiate()'   to install deps"
  '';
}
