{
  description = "Comp sys perf analysis";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, flake-utils }:
  flake-utils.lib.eachDefaultSystem (system:
    let
        pkgs = nixpkgs.legacyPackages.${system};
        python-env = pkgs.python3.withPackages (p: [
          p.jupyter
          p.notebook
          p.pandas
          p.matplotlib
          p.numpy
        ]);
    in {
      devShells.default = pkgs.mkShell {
        packages = [ python-env ];
        buildInputs = with pkgs; [
          marp-cli
          texliveFull
        ];
      };
    }
  );
}
