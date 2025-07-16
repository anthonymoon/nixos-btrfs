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
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    disko,
    ...
  } @ inputs: let
    system = "x86_64-linux";

    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

    lib = nixpkgs.lib;
  in {
    nixosConfigurations = {
      nixos = lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs self;};

        modules = [
          # Disko
          disko.nixosModules.disko

          # Hardware
          ./hosts/nixos/hardware-configuration.nix
          ./hosts/nixos/disk-config.nix

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
          ./modules/maintenance.nix
          ./modules/binary-cache.nix

          # Home Manager
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.amoon = import ./home.nix;
          }

          # Host specific configuration
          ./hosts/nixos/configuration.nix
        ];
      };
    };

    # Development shell
    devShells.${system}.default = pkgs.mkShell {
      packages = with pkgs; [
        nixos-rebuild
        nh
        nix-output-monitor
        nvd
        statix
        deadnix
        alejandra
        git
      ];

      shellHook = ''
        echo "NixOS Development Environment"
        echo ""
        echo "System rebuild:"
        echo "  sudo nixos-rebuild switch --flake .#nixos"
        echo ""
        echo "Fresh installation:"
        echo "  sudo nix run .#install"
        echo ""
        echo "Flake commands:"
        echo "  nix flake update"
        echo "  nix flake check"
        echo "  nix fmt"
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
      install = {
        type = "app";
        program = "${pkgs.writeShellScriptBin "nixos-installer" ''
          #!/usr/bin/env bash
          set -euo pipefail

          echo "NixOS Installer"
          echo "==============="
          echo ""
          echo "This will install NixOS with configuration from:"
          echo "https://github.com/anthonymoon/nixos-btrfs"
          echo ""
          echo "WARNING: This will ERASE the target disk!"
          echo ""

          # Default values
          DISK="''${1:-/dev/sda}"
          FLAKE_URL="github:anthonymoon/nixos-btrfs#nixos"

          # Show disk info
          echo "Target disk: $DISK"
          echo ""
          if [[ -b "$DISK" ]]; then
              echo "Disk information:"
              lsblk "$DISK" || true
              echo ""
          else
              echo "ERROR: $DISK is not a block device"
              exit 1
          fi

          # Confirmation
          read -p "Continue with installation to $DISK? (yes/no): " confirm
          if [[ "$confirm" != "yes" ]]; then
              echo "Installation cancelled"
              exit 0
          fi

          echo ""
          echo "Starting installation..."
          echo ""

          # Partition and format disk
          echo "==> Partitioning disk with disko..."
          nix --extra-experimental-features "nix-command flakes" run github:nix-community/disko -- --mode disko --flake "$FLAKE_URL"

          # Install NixOS
          echo ""
          echo "==> Installing NixOS..."
          nixos-install --flake "$FLAKE_URL" --no-root-password --no-write-lock-file

          echo ""
          echo "Installation complete!"
          echo ""
          echo "Next steps:"
          echo "1. Reboot into your new system"
          echo "2. Set user password: passwd amoon"
          echo "3. Deploy updates: sudo nixos-rebuild switch --flake github:anthonymoon/nixos-btrfs#nixos"
          echo ""
          echo "Enjoy your new NixOS system!"
        ''}/bin/nixos-installer";
      };

      run-vm = {
        type = "app";
        program = "${self.nixosConfigurations.nixos.config.system.build.vm}/bin/run-nixos-vm";
      };
    };
  };
}
