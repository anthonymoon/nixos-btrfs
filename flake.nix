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

      # Boot configuration with CachyOS kernel
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      # CachyOS kernel for better performance
      boot.kernelPackages = pkgs.linuxPackages_cachyos;

      # Sched-ext scheduler support
      services.scx = {
        enable = true;
        scheduler = "scx_rustland"; # Can also use scx_rusty, scx_lavd, etc.
        package = pkgs.scx_git.full;
      };

      # ZFS configuration
      boot.supportedFilesystems = ["zfs"];
      boot.zfs.forceImportRoot = false;
      boot.zfs.requestEncryptionCredentials = false;
      # Set a proper unique hostId (required for ZFS)
      networking.hostId = "abcd1234";

      # ZFS services
      services.zfs.autoScrub.enable = true;
      services.zfs.autoSnapshot.enable = true;

      # ZFS boot optimizations
      boot.kernelParams = [
        "zfs.zfs_arc_max=2147483648" # 2GB ARC max for smaller systems
      ];

      # Ensure ZFS pool imports at boot
      boot.zfs.extraPools = ["zroot"];

      # Enable ZFS in initrd
      boot.initrd.supportedFilesystems = ["zfs"];

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

      # HDR support (experimental module from Chaotic)
      chaotic.hdr.enable = true;

      # Mesa Git for latest GPU drivers
      chaotic.mesa-git.enable = true;
      chaotic.mesa-git.extraPackages = with pkgs; [
        intel-media-driver
        vaapiIntel
      ];

      hardware.opengl = {
        enable = true;
        driSupport = true;
        driSupport32Bit = true;
      };

      # System packages with Chaotic bleeding-edge versions
      environment.systemPackages = with pkgs; [
        # System tools
        git
        vim
        wget
        curl
        htop
        btop

        # ZFS tools (with CachyOS optimizations)
        zfs
        zfs_cachyos

        # Development tools (bleeding-edge versions)
        fd
        ripgrep
        eza
        bat
        ncdu
        helix_git # Post-modern modal editor

        # Gaming (Chaotic enhanced packages)
        lutris
        wine
        discord-krisp # Discord with noise suppression
        mangohud_git # Latest MangoHUD
        gamescope_git # SteamOS compositor

        # Bleeding-edge browsers
        firefox_nightly

        # Performance tools
        scx_git.full # sched-ext schedulers
        ananicy-rules-cachyos_git

        # Media tools
        mpv-vapoursynth # Enhanced mpv with VapourSynth

        # Communication
        telegram-desktop_git

        # System monitoring
        mangohud_git
        openrgb_git # RGB lighting control
      ];

      # Advanced scheduler configuration
      services.ananicy = {
        enable = true;
        package = pkgs.ananicy-cpp;
        rulesProvider = pkgs.ananicy-rules-cachyos_git;
      };

      # Nix configuration with Chaotic binary cache
      nix.settings = {
        experimental-features = ["nix-command" "flakes"];
        auto-optimise-store = true;
        # Binary cache is automatically configured by chaotic.nixosModules.default
      };

      # Allow unfree packages
      nixpkgs.config.allowUnfree = true;

      # Additional Chaotic optimizations
      chaotic.nyx.cache.enable = true;
      chaotic.nyx.overlay.enable = true;
      chaotic.nyx.registry.enable = true;

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

      # Graphics with bleeding-edge Mesa
      hardware.opengl.extraPackages = with pkgs; [
        mesa.drivers
      ];

      # Chaotic Nyx optimizations for VMs
      chaotic.mesa-git.enable = true;
      chaotic.mesa-git.extraPackages = with pkgs; [
        intel-media-driver
      ];

      # VM-specific gaming setup
      environment.systemPackages = with pkgs; [
        gamescope_git
        mangohud_git
      ];
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
      # AMD GPU support with latest drivers
      hardware.opengl.extraPackages = with pkgs; [
        amdvlk
      ];
      boot.kernelModules = ["amdgpu"];

      # Advanced Chaotic Nyx optimizations for bare metal
      chaotic.mesa-git.enable = true;
      chaotic.mesa-git.extraPackages = with pkgs; [
        mesa_git.opencl
      ];

      # Gaming optimizations with CachyOS
      programs.steam.package = pkgs.steam.override {
        extraPkgs = pkgs:
          with pkgs; [
            mangohud_git
            gamescope_git
            gamemode
          ];
      };

      # Enable Proton CachyOS
      environment.systemPackages = with pkgs; [
        proton-cachyos
        luxtorpeda # Native Linux game engines
      ];
    };

    # Disko ZFS configuration
    diskoConfig = {
      config,
      lib,
      ...
    }: let
      diskDevice = lib.mkDefault "/dev/disk/by-id/PLACEHOLDER";
    in {
      disko.devices = {
        disk = {
          main = {
            type = "disk";
            device = diskDevice;
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
              acltype = "posixacl";
              canmount = "off";
              dnodesize = "auto";
              normalization = "formD";
              relatime = "on";
              xattr = "sa";
              mountpoint = "none";
            };
            datasets = {
              # Root system container - canmount=noauto, mountpoint=legacy
              "root" = {
                type = "zfs_fs";
                options = {
                  canmount = "noauto";
                  mountpoint = "legacy";
                };
              };
              # Actual root filesystem under the container
              "root/nixos" = {
                type = "zfs_fs";
                mountpoint = "/";
                options = {
                  compression = "lz4";
                };
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
                  atime = "off";
                };
              };
              "persist" = {
                type = "zfs_fs";
                mountpoint = "/persist";
                options = {
                  compression = "lz4";
                };
              };
              "reserved" = {
                type = "zfs_fs";
                options = {
                  refreservation = "10G";
                  canmount = "off";
                };
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
      qemu-image =
        (nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            "${nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
            disko.nixosModules.disko
            chaotic.nixosModules.default
            diskoConfig
            baseConfig
            qemuConfig
            {
              virtualisation.diskSize = 20480; # 20GB
              virtualisation.memorySize = 4096; # 4GB RAM
            }
          ];
        }).config.system.build.vm;

      # HyperV VHD image
      hyperv-image =
        (nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            "${nixpkgs}/nixos/modules/virtualisation/hyperv-image.nix"
            disko.nixosModules.disko
            diskoConfig
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
          --flake ".#nixos-$PLATFORM"

        # Install NixOS
        sudo nixos-install --flake ".#nixos-$PLATFORM"

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
