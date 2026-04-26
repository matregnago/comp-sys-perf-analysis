{
  description = "CMP223 - HPC Environment com FHS para vLLM e Ray no PCAD";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          cudaSupport = true;
        };
      };

      hostMounts = [
        "/usr/lib/x86_64-linux-gnu"
        "/usr/lib64"
        "/usr/bin"
      ];

      mkBindArgs =
        paths:
        builtins.concatMap (p: [
          "--ro-bind-try"
          p
          "/host${p}"
        ]) paths;

      pcadFhs = pkgs.buildFHSEnv {
        name = "pcad-fhs";

        targetPkgs =
          ps: with ps; [
            cudaPackages.cudatoolkit
            cudaPackages.cuda_nvcc
            cudaPackages.nsight_systems
            cudaPackages.nsight_compute
            gcc
            git
            uv
            python313
            zlib
            zstd
            glib
            libGL
            stdenv.cc.cc.lib
          ];

        extraBwrapArgs = mkBindArgs hostMounts;

        profile = ''
          export CUDA_HOME=${pkgs.cudaPackages.cudatoolkit}

          DRIVER_BASE="''${SCRATCH:-/scratch/''${USER:-$LOGNAME}}"
          DRIVER_DIR="$DRIVER_BASE/pcad-cuda-drivers"
          mkdir -p "$DRIVER_DIR"
          rm -f "$DRIVER_DIR"/libcuda.so* "$DRIVER_DIR"/libnvidia-ml.so* "$DRIVER_DIR"/nvidia-smi
          for d in /host/usr/lib/x86_64-linux-gnu /host/usr/lib64; do
            [ -d "$d" ] || continue
            for p in "$d"/libcuda.so* "$d"/libnvidia-ml.so*; do
              if [ -e "$p" ] || [ -L "$p" ]; then
                ln -sf "$p" "$DRIVER_DIR/$(basename "$p")"
              fi
            done
          done

          [ -x "/host/usr/bin/nvidia-smi" ] && ln -sf /host/usr/bin/nvidia-smi "$DRIVER_DIR/nvidia-smi"

          export LD_LIBRARY_PATH="$DRIVER_DIR:${pkgs.cudaPackages.cudatoolkit}/lib64:''${LD_LIBRARY_PATH:-}"
          export PATH="$DRIVER_DIR:${pkgs.cudaPackages.cudatoolkit}/bin:$PATH"
        '';

        runScript = "bash";
      };

    in
    {
      packages.${system}.default = pcadFhs;

      devShells.${system} = {
        default = pcadFhs.env;
        tools = pkgs.mkShell {
          packages = with pkgs; [
            marp-cli
            texliveFull
            chromium
            python313
            uv
          ];
        };
      };
    };
}
