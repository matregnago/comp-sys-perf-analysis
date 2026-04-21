{
  description = "";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      cudaCommon = with pkgs; [
        python313
        uv
        cudaPackages.cudatoolkit
        cudaPackages.cuda_nvcc
        cudaPackages.nsight_systems
        cudaPackages.nsight_compute
        gcc
        git
      ];
      mkCudaHook = driverGlobs: ''
        export CUDA_HOME=${pkgs.cudaPackages.cudatoolkit}

        DRIVER_DIR="$(mktemp -d)"
        for p in ${driverGlobs}; do
          [ -e "$p" ] && ln -sf "$p" "$DRIVER_DIR/$(basename "$p")"
        done

        export LD_LIBRARY_PATH=$DRIVER_DIR:${pkgs.cudaPackages.cudatoolkit}/lib64:${
          pkgs.lib.makeLibraryPath [
            pkgs.stdenv.cc.cc # libstdc++, libgcc_s
            pkgs.zlib # libz   (numpy)
            pkgs.zstd # libzstd (torch)
            pkgs.libGL # libGL  (opencv/torchvision)
            pkgs.glib # libgthread (opencv)
          ]
        }:$LD_LIBRARY_PATH
        export PATH=${pkgs.cudaPackages.cudatoolkit}/bin:$PATH
      '';

      pcadHook = mkCudaHook "/usr/lib/x86_64-linux-gnu/libcuda.so* /usr/lib/x86_64-linux-gnu/libnvidia-ml.so*";
    in
    {
      devShells.${system} = {
        pcad = pkgs.mkShell {
          packages = cudaCommon;
          shellHook = pcadHook;
        };

        default = pkgs.mkShell {
          packages = with pkgs; [
            marp-cli
            texliveFull
            chromium
          ];
          shellHook = ''
            uv sync --extra dev
          '';
        };
      };
    };
}
