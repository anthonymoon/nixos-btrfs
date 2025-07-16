{
  description = "NixOS ZFS Installation System with Multi-Platform Support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
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
    chaotic,
    home-manager,
    disko,
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};

    # Common configuration shared across all platforms
    baseConfig = {
      config,
      lib,
      pkgs,
      modulesPath,
      ...
    }: {
      imports = [
        ./hardware-configuration.nix
        home-manager.nixosModules.home-manager
      ];

      # Core system configuration
      networking.hostName = "nixos-dev1";
      networking.domain = "dirtybit.co";

      # User configuration
      users.users.amoon = {
        isNormalUser = true;
        description = "Anthony Moon";
        extraGroups = ["wheel" "networkmanager" "video" "audio"];
        shell = pkgs.fish;
      };

      # Enable fish shell
      programs.fish.enable = true;

      # Home Manager configuration
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        users.amoon = import ./home.nix;
      };

      # Hardware and boot configuration moved to hardware-configuration.nix

      # Network configuration
      networking.networkmanager.enable = false;
      networking.useNetworkd = true;
      networking.useDHCP = false;
      systemd.network = {
        enable = true;
        networks."10-ethernet" = {
          matchConfig.Type = "ether";
          DHCP = "yes";
          dhcpV4Config.UseDNS = false;
          dhcpV6Config.UseDNS = false;
        };
      };
      networking.nameservers = ["94.140.14.14" "94.140.15.15"];

      # ZRAM swap
      zramSwap = {
        enable = true;
        memoryPercent = 100;
        algorithm = "zstd";
      };

      # Desktop environment - Hyprland
      programs.hyprland.enable = true;
      services.greetd = {
        enable = true;
        settings = {
          default_session = {
            command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd Hyprland";
            user = "greeter";
          };
        };
      };

      # Gaming support
      programs.steam.enable = true;
      programs.gamemode.enable = true;

      hardware.graphics = {
        enable = true;
        enable32Bit = true;
      };

      # System packages (base installation)
      environment.systemPackages = with pkgs; [
        # System tools
        git
        vim
        wget
        curl
        htop
        btop

        # ZFS tools
        zfs

        # Development tools
        fd
        ripgrep
        eza
        bat
        ncdu

        # Gaming (basic packages)
        lutris
        wine

        # Media tools
        firefox
        mpv
      ];

      # Nix configuration
      nix.settings = {
        experimental-features = ["nix-command" "flakes"];
        auto-optimise-store = true;
      };

      # Allow unfree packages
      nixpkgs.config.allowUnfree = true;

      # System version
      system.stateVersion = "24.05";
    };
    # Platform-specific configurations
    # QEMU configuration moved to hardware-configuration.nix
    # Removed HyperV and bare metal configs - QEMU only
    # Removed old zroot disko config - using rpool config in disko-config-rpool.nix
  in {
    # NixOS configurations for different platforms
    nixosConfigurations = {
      # QEMU VM configuration with rpool
      nixos-dev1 = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          ./disko-config-rpool.nix
          baseConfig
        ];
      };

      # Legacy config removed
      nixos-dev-chaotic-removed = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          baseConfig
          ({
            config,
            lib,
            pkgs,
            ...
          }: {
            # Chaotic Nyx bleeding-edge configuration for QEMU
            boot.kernelPackages = pkgs.linuxPackages_cachyos;

            chaotic.mesa-git.enable = true;
            chaotic.nyx.cache.enable = true;
            chaotic.nyx.overlay.enable = true;
            chaotic.nyx.registry.enable = true;

            environment.systemPackages = with pkgs; [
              firefox_nightly
            ];
          })
        ];
      };

      # QEMU VM configuration with Chaotic Nyx (use AFTER base installation)
      nixos-dev1-chaotic = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          chaotic.nixosModules.default
          baseConfig
          ({
            config,
            lib,
            pkgs,
            ...
          }: {
            # Chaotic Nyx configuration for VMs
            chaotic.mesa-git.enable = true;
            chaotic.nyx.cache.enable = true;
            chaotic.nyx.overlay.enable = true;
            chaotic.nyx.registry.enable = true;

            environment.systemPackages = with pkgs; [
              gamescope_git
              mangohud_git
              firefox_nightly
            ];
          })
        ];
      };
    };

    # Build outputs
    packages.${system} = {
      # ISO image
      iso =
        (nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            {
              nixpkgs.hostPlatform = system;
              environment.systemPackages = with pkgs; [
                git
                curl
                wget
                zfs
              ];
              # Include this flake in the ISO
              nix.registry.nixos-config.flake = self;
              environment.etc."install-config/flake.nix".source = ./flake.nix;
              environment.etc."install-config/home.nix".source = ./home.nix;
            }
          ];
        }).config.system.build.isoImage;

      # QEMU image
      qemu-image =
        (nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            "${nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
            disko.nixosModules.disko
            ./disko-config-rpool.nix
            baseConfig
            {
              virtualisation.diskSize = 20480; # 20GB
              virtualisation.memorySize = 4096; # 4GB RAM
            }
          ];
        }).config.system.build.vm;

      # Installation script
      install-script = pkgs.writeScriptBin "nixos-install-zfs" ''
        #!${pkgs.bash}/bin/bash
        export FLAKE_URL="github:yourusername/nixos-config"
        ${builtins.readFile ./install-nixos.sh}
      '';

      # Deployment script
      deploy = pkgs.writeScriptBin "deploy-nixos" ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail

        DISK="''${1:-auto}"
        PLATFORM="''${2:-auto}"

        if [[ "$DISK" == "auto" ]]; then
          for disk in /dev/sda /dev/vda /dev/nvme0n1; do
            if [[ -b "$disk" ]]; then
              DISK="$disk"
              break
            fi
          done
        fi

        # Always use QEMU platform
        PLATFORM="qemu"

        echo "Deploying NixOS with ZFS to $DISK (platform: $PLATFORM)"

        # Find disk ID or use direct path
        if [[ -d /dev/disk/by-id ]]; then
          # Find the disk ID that points to our disk (not partitions)
          DISK_ID=$(ls -la /dev/disk/by-id/ | grep " -> .*$(basename "$DISK")$" | grep -v "part" | head -1 | awk '{print $9}' || echo "")
          if [[ -n "$DISK_ID" ]]; then
            DEVICE_PATH="/dev/disk/by-id/$DISK_ID"
          else
            DEVICE_PATH="$DISK"
          fi
        else
          DEVICE_PATH="$DISK"
        fi

        echo "Using device: $DEVICE_PATH"

        # Load ZFS modules
        sudo modprobe zfs

        # Create temporary flake with correct device
        TEMP_DIR=$(mktemp -d)
        cd "$TEMP_DIR"

        # Clone the repo and modify device
        git clone https://github.com/anthonymoon/nixos-zfsroot.git .
        sed -i "s|/dev/disk/by-id/PLACEHOLDER|$DEVICE_PATH|g" flake.nix

        # Install using disko
        sudo nix --extra-experimental-features "nix-command flakes" run github:nix-community/disko -- --mode disko \
          --flake ".#nixos-dev1"

        # Install NixOS
        sudo nixos-install --flake ".#nixos-dev1"

        # Cleanup
        cd /
        rm -rf "$TEMP_DIR"

        echo "Installation complete! Reboot to start your new system."
      '';
    };

    # Development shell
    devShells.${system}.default = pkgs.mkShell {
      buildInputs = with pkgs; [
        # Nix tools
        nixos-rebuild
        nixpkgs-fmt
        # Development tools
        git
        # Virtualization tools
        qemu
        # ZFS tools
        zfs
      ];

      shellHook = ''
        echo "NixOS ZFS Development Environment"
        echo "Available commands:"
        echo "  nix build .#iso           - Build ISO image"
        echo "  nix build .#qemu-image    - Build QEMU image"
        echo "  nix run .#deploy          - Deploy to system"
        echo "  nix run .#install-script  - Run installer script"
      '';
    };

    # Apps for easy running
    apps.${system} = {
      install-script = {
        type = "app";
        program = "${self.packages.${system}.install-script}/bin/nixos-install-zfs";
      };

      deploy = {
        type = "app";
        program = "${self.packages.${system}.deploy}/bin/deploy-nixos";
      };

      run-qemu = {
        type = "app";
        program = toString (pkgs.writeScript "run-qemu" ''
          #!${pkgs.bash}/bin/bash
          ${pkgs.qemu}/bin/qemu-system-x86_64 \
            -enable-kvm \
            -m 4096 \
            -smp 2 \
            -drive file=nixos.qcow2,if=virtio \
            -netdev user,id=net0 \
            -device virtio-net,netdev=net0 \
            -vga virtio \
            -display gtk
        '');
      };
    };
  };
}
