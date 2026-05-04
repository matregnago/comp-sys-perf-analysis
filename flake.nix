{
  description = "Comp sys perf analysis";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:

      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        python-env = pkgs.python3.withPackages (p: [
          p.jupyter
          p.notebook
          p.pandas
          p.matplotlib
          p.numpy
          p.seaborn
          p.torch
          p.transformers
          p.accelerate
        ]);

      in {
        devShells = {

          default = pkgs.mkShell {
            packages = [
              python-env
              pkgs.marp-cli
              pkgs.texliveFull
              pkgs.chromium
              pkgs.basedpyright
            ];
          };

          pcad = pkgs.mkShell {
            packages = [
              python-env
              pkgs.cudaPackages.cudatoolkit
              pkgs.cudaPackages.nsight_compute
              pkgs.cudaPackages.nsight_systems
            ];

            shellHook = ''
              export LD_LIBRARY_PATH=${pkgs.cudaPackages.cudatoolkit}/lib:$LD_LIBRARY_PATH
            '';
          };

        };
      }
    );
}