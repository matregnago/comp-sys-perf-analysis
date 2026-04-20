{
  description = "";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }:
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

    cudaShellHook = ''
      export CUDA_HOME=${pkgs.cudaPackages.cudatoolkit}
      # Driver libcuda.so vem do host: /usr/lib/wsl/lib (WSL) ou
      # /usr/lib/x86_64-linux-gnu (Linux normal/PCAD). Path inexistente é ignorado
      # pelo loader, entao incluir os dois e' seguro nos dois lugares.
      export LD_LIBRARY_PATH=/usr/lib/wsl/lib:/usr/lib/x86_64-linux-gnu:${pkgs.cudaPackages.cudatoolkit}/lib64:${pkgs.lib.makeLibraryPath [
        pkgs.stdenv.cc.cc            # libstdc++, libgcc_s
        pkgs.zlib                    # libz   (numpy)
        pkgs.zstd                    # libzstd (torch)
        pkgs.libGL                   # libGL  (opencv/torchvision)
        pkgs.glib                    # libgthread (opencv)
      ]}:$LD_LIBRARY_PATH
      export PATH=${pkgs.cudaPackages.cudatoolkit}/bin:$PATH
    '';
  in
  {
    devShells.${system} = {
      pcad = pkgs.mkShell {
        packages = cudaCommon;
        shellHook = cudaShellHook;
      };
      default = pkgs.mkShell {
        packages = cudaCommon ++ (with pkgs; [
          marp-cli
          texliveFull
          chromium                  
        ]);
        shellHook = cudaShellHook;
      };
    };
  };
}
