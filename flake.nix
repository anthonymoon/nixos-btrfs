{
  description = "NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    disko,
    lanzaboote,
    nixos-hardware,
    ...
  } @ inputs: let
    system = "x86_64-linux";

    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

    lib = nixpkgs.lib;

    # Helper function to create a NixOS system configuration
    mkSystem = {
      hostname,
      diskConfig ? "btrfs-single",
      extraModules ? [],
    }:
      lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs self;};
        modules =
          [
            # Core disko integration
            disko.nixosModules.disko

            # Disk configuration
            ./modules/disko/${diskConfig}.nix

            # System modules
            ./modules/system/performance.nix
            ./modules/system/boot.nix
            ./modules/system/maintenance.nix

            # Hardware detection
            ./hosts/${hostname}/hardware-configuration.nix

            # Core modules
            ./modules/core.nix
            ./modules/networking.nix
            ./modules/nix-config.nix

            # Service modules
            ./modules/desktop.nix
            ./modules/gaming.nix
            ./modules/media-server.nix
            ./modules/development.nix
            ./modules/virtualization.nix
            ./modules/filesystems.nix
            ./modules/snapshots.nix
            ./modules/binary-cache.nix

            # Home Manager
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.amoon = import ./home.nix;
            }

            # Host specific configuration
            ./hosts/${hostname}/configuration.nix

            # Enable new system modules
            {
              system.performance.enable = true;
              system.boot.enable = true;
              maintenance.enable = true;

              # Set hostname
              networking.hostName = hostname;
            }
          ]
          ++ extraModules;
      };
  in {
    nixosConfigurations = {
      # Main desktop/workstation - BTRFS with encryption
      nixos = mkSystem {
        hostname = "nixos";
        diskConfig = "btrfs-luks";
        extraModules = [
          # Enable TPM and secure boot for encrypted system
          {
            disko.encryption.tpmSupport = true;
            system.boot.enableTPM = true;
            # Optionally enable secure boot (requires manual setup)
            # system.boot.secureBoot = true;
          }
        ];
      };

      # Minimal VM configuration with ZFS
      vm = mkSystem {
        hostname = "vm";
        diskConfig = "zfs-single";
        extraModules = [
          {
            # VM-specific optimizations
            services.qemuGuest.enable = true;
            boot.kernelParams = ["console=ttyS0"];
          }
        ];
      };

      # Example additional hosts (uncomment and customize as needed)

      # # Laptop configuration with single BTRFS
      # laptop = mkSystem {
      #   hostname = "laptop";
      #   diskConfig = "btrfs-single";
      #   extraModules = [
      #     nixos-hardware.nixosModules.common-laptop
      #     nixos-hardware.nixosModules.common-laptop-ssd
      #   ];
      # };

      # # Server with ZFS mirror
      # server = mkSystem {
      #   hostname = "server";
      #   diskConfig = "zfs-mirror";
      #   extraModules = [
      #     { services.openssh.enable = true; }
      #   ];
      # };

      # # Workstation with single ZFS disk
      # workstation = mkSystem {
      #   hostname = "workstation";
      #   diskConfig = "zfs-single";
      #   extraModules = [
      #     nixos-hardware.nixosModules.common-gpu-nvidia
      #     { system.performance.disableMitigations = true; }
      #   ];
      # };
    };

    # Development shell with enhanced tools
    devShells.${system}.default = pkgs.mkShell {
      packages = with pkgs; [
        # Nix tools
        nixos-rebuild
        nh
        nix-output-monitor
        nvd
        statix
        deadnix
        alejandra

        # Disko and installation tools
        disko.packages.${system}.disko
        util-linux
        parted
        smartmontools

        # System tools
        git
        jq
        rsync

        # Filesystem tools
        btrfs-progs
        zfs

        # Monitoring and debugging
        btop
        iotop

        # TPM tools (for encryption)
        tpm2-tools
      ];

      shellHook = ''
        echo "NixOS Disko Development Environment"
        echo "=================================="
        echo ""
        echo "Installation commands:"
        echo "  ./scripts/install-interactive.sh  # Interactive installer"
        echo "  ./scripts/mount-system.sh         # Mount existing system"
        echo ""
        echo "Manual disko commands:"
        echo "  sudo nix run github:nix-community/disko#disko-install -- --flake .#nixos"
        echo "  sudo disko --mode disko --flake .#nixos"
        echo ""
        echo "System rebuild:"
        echo "  sudo nixos-rebuild switch --flake .#nixos"
        echo ""
        echo "Available disk configurations:"
        echo "  - btrfs-single: Single disk BTRFS"
        echo "  - btrfs-luks:   Encrypted BTRFS with TPM2"
        echo "  - zfs-single:   Single disk ZFS"
        echo "  - zfs-mirror:   ZFS mirror (2 disks)"
        echo ""
        echo "Flake commands:"
        echo "  nix flake update"
        echo "  nix flake check"
        echo "  nix fmt"
        echo ""
        echo "Example hosts:"
        echo "  nixos       - Main system (btrfs-luks)"
        echo "  laptop      - Laptop system (btrfs-single) [commented]"
        echo "  server      - Server system (zfs-mirror) [commented]"
        echo "  workstation - Workstation (zfs-single) [commented]"
      '';
    };

    # Formatter
    formatter.${system} = pkgs.alejandra;

    # Packages for building images
    packages.${system} = {
      # ISO image
      iso =
        (nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            {
              nixpkgs.hostPlatform = system;
              isoImage.squashfsCompression = "zstd -Xcompression-level 6";

              environment.systemPackages = with pkgs; [
                git
                curl
                wget
                vim
              ];

              # Include installer script
              environment.etc."installer/install.sh".source = ./install.sh;

              # Enable SSH in installer
              services.openssh.enable = true;

              # Set root password for installer (change this!)
              users.users.root.initialHashedPassword = "";

              system.stateVersion = "24.05";
            }
          ];
        }).config.system.build.isoImage;

      # QEMU VM image
      vm = self.nixosConfigurations.nixos.config.system.build.vm;

      # Build script for QEMU image
      build-qemu = pkgs.writeShellScriptBin "build-qemu" ''
        #!/usr/bin/env bash
        echo "Building QEMU qcow2 image..."
        echo "This will create a 20GB image with the NixOS configuration"
        echo ""
        echo "Note: You'll need to:"
        echo "1. Boot the image"
        echo "2. Run the installer inside: curl -sL https://raw.githubusercontent.com/anthonymoon/nixos-btrfs/main/install.sh | sudo bash"
        echo ""
        # Build a basic qcow2 with installer
        nix build nixpkgs#nixosConfigurations.installer.config.system.build.qcow2
      '';

      # Build script for Hyper-V image
      build-hyperv = pkgs.writeShellScriptBin "build-hyperv" ''
        #!/usr/bin/env bash
        echo "Building Hyper-V VHDX image..."
        echo "This will create a 20GB image with the NixOS configuration"
        echo ""
        echo "Note: You'll need to:"
        echo "1. Import the VHDX into Hyper-V as Gen 2 VM"
        echo "2. Run the installer inside: curl -sL https://raw.githubusercontent.com/anthonymoon/nixos-btrfs/main/install.sh | sudo bash"
        echo ""
        # Build a basic VHDX with installer
        nix build nixpkgs#nixosConfigurations.installer.config.system.build.hypervImage
      '';
    };

    # Apps for direct execution
    apps.${system} = {
      # Interactive installer
      install = {
        type = "app";
        program = let
          installScript = pkgs.writeShellScriptBin "install-interactive" ''
            #!/usr/bin/env bash
            export PATH="${pkgs.lib.makeBinPath [
              pkgs.jq
              pkgs.git
              pkgs.coreutils
              pkgs.util-linux
              pkgs.btrfs-progs
              pkgs.zfs
              pkgs.cryptsetup
              pkgs.parted
              pkgs.gawk
              pkgs.gnugrep
              pkgs.gnused
              pkgs.findutils
            ]}:$PATH"
            exec ${./scripts/install-interactive.sh}
          '';
        in "${installScript}/bin/install-interactive";
      };

      # System mount tool
      mount = {
        type = "app";
        program = let
          mountScript = pkgs.writeShellScriptBin "mount-system" ''
            #!/usr/bin/env bash
            export PATH="${pkgs.lib.makeBinPath [
              pkgs.coreutils
              pkgs.util-linux
              pkgs.btrfs-progs
              pkgs.zfs
              pkgs.cryptsetup
              pkgs.gnugrep
              pkgs.gnused
              pkgs.findutils
            ]}:$PATH"
            exec ${./scripts/mount-system.sh}
          '';
        in "${mountScript}/bin/mount-system";
      };

      # Direct disko install
      disko-install = {
        type = "app";
        program = "${pkgs.writeShellScriptBin "disko-install" ''
          #!/usr/bin/env bash
          set -euo pipefail

          HOST="''${1:-nixos}"
          DISK="''${2:-}"

          echo "NixOS Disko Installer"
          echo "===================="
          echo "Host: $HOST"

          if [[ -n "$DISK" ]]; then
            echo "Disk: $DISK"
            exec sudo nix --extra-experimental-features 'nix-command flakes' run github:nix-community/disko#disko-install -- \
              --flake "github:anthonymoon/nixos-btrfs#$HOST" --disk main "$DISK" --write-efi-boot-entries
          else
            echo "Using auto-detected disk"
            exec sudo nix --extra-experimental-features 'nix-command flakes' run github:nix-community/disko#disko-install -- \
              --flake "github:anthonymoon/nixos-btrfs#$HOST" --write-efi-boot-entries
          fi
        ''}/bin/disko-install";
      };

      # Run VM for testing
      run-vm = {
        type = "app";
        program = "${self.nixosConfigurations.nixos.config.system.build.vm}/bin/run-nixos-vm";
      };

      # Test binary cache
      test-cache = {
        type = "app";
        program = "${pkgs.writeShellScriptBin "test-cache" ''
          #!/usr/bin/env bash
          exec ${./scripts/test-binary-cache.sh} "''${@}"
        ''}/bin/test-cache";
      };
    };
  };
}
