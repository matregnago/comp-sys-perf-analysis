{
  description = "Comp sys perf analysis";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
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
          p.vllm
        ]);
      in
      {
        devShells = {
          default = pkgs.mkShell {
            packages = [ python-env ];
            buildInputs = with pkgs; [
              marp-cli
              texliveFull
              chromium
              basedpyright
              python311Packages.python
            ];
          };
          pcad = pkgs.mkShell {
            packages = [ python-env ];
            buildInputs = with pkgs; [
              cudaPackages.nsight_compute
              cudaPackages.nsight_systems
              cudaPackages.cudatoolkit
            ];
          };
        };
      }
    );
}
