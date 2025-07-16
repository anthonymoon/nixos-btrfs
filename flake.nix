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

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    disko,
    deploy-rs,
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

    deploy = {
      nodes = {
        deadbeef = {
          hostname = "deadbeef.dirtybit.co";
          profiles = {
            system = {
              sshUser = "amoon";
              user = "root";
              path = deploy-rs.lib.${system}.activate.nixos self.nixosConfigurations.nixos;
            };
          };
        };
      };

      # Optional: auto rollback on failure
      autoRollback = true;
      magicRollback = true;
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
        deploy-rs
      ];

      shellHook = ''
        echo "NixOS Development Environment"
        echo ""
        echo "System rebuild:"
        echo "  sudo nixos-rebuild switch --flake .#nixos"
        echo ""
        echo "Remote deployment:"
        echo "  deploy .#deadbeef"
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

    # Checks for deploy-rs
    checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;

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
          echo "https://github.com/anthonymoon/nixos-zfsroot"
          echo ""
          echo "WARNING: This will ERASE the target disk!"
          echo ""

          # Default values
          DISK="''${1:-/dev/sda}"
          FLAKE_URL="github:anthonymoon/nixos-zfsroot#nixos"

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
          nixos-install --flake "$FLAKE_URL" --no-root-password

          echo ""
          echo "Installation complete!"
          echo ""
          echo "Next steps:"
          echo "1. Reboot into your new system"
          echo "2. Set user password: passwd amoon"
          echo "3. Deploy updates: sudo nixos-rebuild switch --flake github:anthonymoon/nixos-zfsroot#nixos"
          echo ""
          echo "Enjoy your new NixOS system!"
        ''}/bin/nixos-installer";
      };
    };
  };
}
