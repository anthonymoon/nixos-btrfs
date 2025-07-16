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
  };
}
