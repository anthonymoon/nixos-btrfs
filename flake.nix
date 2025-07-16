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
        "${modulesPath}/installer/scan/not-detected.nix"
        home-manager.nixosModules.home-manager
      ];

      # Core system configuration
      networking.hostName = "nixos-dev";
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

      # ZFS configuration
      boot.supportedFilesystems = ["zfs"];
      boot.zfs.forceImportRoot = false;
      services.zfs.autoScrub.enable = true;
      services.zfs.autoSnapshot.enable = true;
      networking.hostId = "12345678"; # Required for ZFS

      # Network configuration
      networking.networkmanager.enable = false;
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

      # Gaming support with Chaotic enhancements
      programs.steam.enable = true;
      programs.gamemode.enable = true;
      hardware.opengl = {
        enable = true;
      };

      # System packages
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
        # Gaming (enhanced with Chaotic packages)
        lutris
        wine
        discord
        # Chaotic packages for better performance
        mangohud
        gamemode
      ];

      # Nix configuration
      nix.settings = {
        experimental-features = ["nix-command" "flakes"];
        auto-optimise-store = true;
      };

      # System version
      system.stateVersion = "24.05";
    };

    # Platform-specific configurations
    qemuConfig = {
      config,
      lib,
      pkgs,
      ...
    }: {
      # QEMU/KVM optimizations
      services.qemuGuest.enable = true;
      services.spice-vdagentd.enable = true;
      boot.kernelModules = ["virtio_balloon" "virtio_console" "virtio_rng"];

      # Graphics
      hardware.opengl.extraPackages = with pkgs; [
        mesa.drivers
      ];

      # Chaotic Nyx optimizations for VMs
      chaotic.mesa-git.enable = true;
      chaotic.scx.enable = true;
    };

    hypervConfig = {
      config,
      lib,
      pkgs,
      ...
    }: {
      # HyperV optimizations
      virtualisation.hypervGuest.enable = true;
      boot.kernelParams = ["video=hyperv_fb:1920x1080"];
    };

    baremetalConfig = {
      config,
      lib,
      pkgs,
      ...
    }: {
      # AMD GPU support
      hardware.opengl.extraPackages = with pkgs; [
        rocm-opencl-icd
        rocm-opencl-runtime
        amdvlk
      ];
      boot.kernelModules = ["amdgpu"];

      # Chaotic Nyx optimizations for bare metal
      chaotic.mesa-git.enable = true;
      chaotic.scx.enable = true;
    };

    # Disko ZFS configuration
    diskoConfig = {
      disko.devices = {
        disk = {
          main = {
            type = "disk";
            device = "/dev/disk/by-id/PLACEHOLDER";
            content = {
              type = "gpt";
              partitions = {
                ESP = {
                  size = "1G";
                  type = "EF00";
                  content = {
                    type = "filesystem";
                    format = "vfat";
                    mountpoint = "/boot";
                  };
                };
                zfs = {
                  size = "100%";
                  content = {
                    type = "zfs";
                    pool = "zroot";
                  };
                };
              };
            };
          };
        };
        zpool = {
          zroot = {
            type = "zpool";
            options = {
              ashift = "12";
              autotrim = "on";
            };
            rootFsOptions = {
              compression = "lz4";
              acltype = "posixacl";
              xattr = "sa";
              relatime = "on";
              normalization = "formD";
            };
            datasets = {
              "root" = {
                type = "zfs_fs";
                mountpoint = "/";
                options.compression = "lz4";
              };
              "home" = {
                type = "zfs_fs";
                mountpoint = "/home";
                options = {
                  compression = "zstd-3";
                  recordsize = "1M";
                };
              };
              "nix" = {
                type = "zfs_fs";
                mountpoint = "/nix";
                options = {
                  compression = "zstd-6";
                  recordsize = "64k";
                  dedup = "on";
                  atime = "off";
                };
              };
              "persist" = {
                type = "zfs_fs";
                mountpoint = "/persist";
                options.compression = "lz4";
              };
              "reserved" = {
                type = "zfs_fs";
                options.refreservation = "10G";
              };
            };
          };
        };
      };
    };
  in {
    # NixOS configurations for different platforms
    nixosConfigurations = {
      # Bare metal configuration
      nixos-dev = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          chaotic.nixosModules.default
          diskoConfig
          baseConfig
          baremetalConfig
        ];
      };

      # QEMU/KVM configuration
      nixos-qemu = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          chaotic.nixosModules.default
          diskoConfig
          baseConfig
          qemuConfig
        ];
      };

      # HyperV configuration (without Chaotic for compatibility)
      nixos-hyperv = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          diskoConfig
          baseConfig
          hypervConfig
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
                (writeScriptBin "nixos-install-zfs" (builtins.readFile ./install-nixos.sh))
              ];
              # Include this flake in the ISO
              nix.registry.nixos-config.flake = self;
              environment.etc."install-config/flake.nix".source = ./flake.nix;
              environment.etc."install-config/home.nix".source = ./home.nix;
            }
          ];
        }).config.system.build.isoImage;

      # QEMU image
      qemu-image = pkgs.writeScript "build-qemu-image" ''
        #!${pkgs.bash}/bin/bash
        echo "Building QEMU image..."

        # Create a simple disk image
        ${pkgs.qemu}/bin/qemu-img create -f qcow2 nixos-qemu.qcow2 20G

        echo "QEMU image created: nixos-qemu.qcow2"
        echo "Use: qemu-system-x86_64 -enable-kvm -m 4096 -drive file=nixos-qemu.qcow2,if=virtio"
      '';

      # HyperV image
      hyperv-image =
        (nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            "${nixpkgs}/nixos/modules/virtualisation/hyperv-image.nix"
            baseConfig
            hypervConfig
          ];
        }).config.system.build.hypervImage;

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

        if [[ "$PLATFORM" == "auto" ]]; then
          if systemd-detect-virt --quiet; then
            case $(systemd-detect-virt) in
              kvm|qemu) PLATFORM="qemu" ;;
              microsoft) PLATFORM="hyperv" ;;
              *) PLATFORM="baremetal" ;;
            esac
          else
            PLATFORM="baremetal"
          fi
        fi

        echo "Deploying NixOS with ZFS to $DISK (platform: $PLATFORM)"

        # Update disko configuration with actual disk
        export DISK_ID=$(ls -la /dev/disk/by-id/ | grep "$(basename "$DISK")" | head -1 | awk '{print $9}')

        # Install using disko
        sudo nix --extra-experimental-features "nix-command flakes" run github:nix-community/disko -- --mode disko \
          --arg device '"'"/dev/disk/by-id/$DISK_ID"'"' \
          --flake "github:anthonymoon/nixos-zfsroot#nixos-$PLATFORM"

        # Install NixOS
        sudo nixos-install --flake "github:anthonymoon/nixos-zfsroot#nixos-$PLATFORM"

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
        echo "  nix build .#hyperv-image  - Build HyperV image"
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
