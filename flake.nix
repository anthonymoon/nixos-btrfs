{
  description = "NixOS ZFS Installation System with Multi-Platform Support";

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

      # Graphics support (no gaming)
      hardware.graphics = {
        enable = true;
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
    qemuConfig = {
      config,
      lib,
      pkgs,
      ...
    }: {
      # QEMU/KVM full integration
      services.qemuGuest.enable = true;
      services.spice-vdagentd.enable = true;

      # Enable QEMU guest agent for better host integration
      services.qemu-guest-agent.enable = true;

      # Virtio modules for best performance
      boot.initrd.availableKernelModules = [
        "virtio_pci"
        "virtio_scsi"
        "virtio_blk"
        "virtio_net"
        "virtio_balloon"
        "virtio_console"
      ];
      boot.kernelModules = ["virtio_balloon" "virtio_console" "virtio_rng"];

      # Graphics optimized for VMs
      hardware.graphics = {
        enable = true;
        extraPackages = with pkgs; [
          mesa.drivers
        ];
      };

      # SPICE integration for clipboard and display
      environment.systemPackages = with pkgs; [
        spice-gtk
        spice-protocol
        spice-vdagent
      ];

      # Optimize for VM environment
      boot.kernelParams = ["console=ttyS0,115200"];

      # Network optimization for virtio
      networking.interfaces.ens3.useDHCP = lib.mkDefault true;
    };

    hypervConfig = {
      config,
      lib,
      pkgs,
      ...
    }: {
      # Full Hyper-V integration
      virtualisation.hypervGuest = {
        enable = true;
        videoMode = "1920x1080";
      };

      # Hyper-V specific kernel modules
      boot.initrd.availableKernelModules = [
        "hv_vmbus"
        "hv_netvsc"
        "hv_storvsc"
        "hv_utils"
        "hv_balloon"
      ];

      boot.kernelParams = [
        "video=hyperv_fb:1920x1080"
        "console=ttyS0,115200"
        "console=tty0"
      ];

      # Enable Hyper-V daemons for time sync, KVP, etc.
      services.hypervkvpd.enable = true;

      # Hyper-V optimized network
      networking.interfaces.eth0.useDHCP = lib.mkDefault true;

      # Install integration tools
      environment.systemPackages = with pkgs; [
        linux-firmware # For Hyper-V synthetic drivers
      ];
    };

    baremetalConfig = {
      config,
      lib,
      pkgs,
      ...
    }: {
      # AMD GPU support with latest drivers
      hardware.graphics.extraPackages = with pkgs; [
        amdvlk
      ];
      boot.kernelModules = ["amdgpu"];

      # Additional packages for bare metal
      environment.systemPackages = with pkgs; [
        # Add any bare metal specific packages here
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
              # Root system container
              "root" = {
                type = "zfs_fs";
                options = {
                  canmount = "off";
                  mountpoint = "none";
                };
              };
              # Actual root filesystem - using legacy mount
              "root/nixos" = {
                type = "zfs_fs";
                mountpoint = "/";
                options = {
                  compression = "lz4";
                  canmount = "noauto";
                  mountpoint = "legacy";
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
      # Bare metal configuration with zroot pool
      nixos-dev = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          diskoConfig
          baseConfig
          baremetalConfig
        ];
      };

      # Btrfs configuration with libre kernel
      nixos-btrfs = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          ./disko-config-btrfs.nix
          ./hardware-configuration-btrfs.nix
          baseConfig
          ({
            config,
            pkgs,
            ...
          }: {
            # Override kernel to use latest libre
            boot.kernelPackages = pkgs.linuxKernel.packages.linux_latest_libre;

            # Btrfs-specific optimizations
            boot.supportedFilesystems = ["btrfs"];

            # Override hardware config to remove proprietary firmware
            hardware.enableRedistributableFirmware = false;

            # Use only free software
            nixpkgs.config.allowUnfree = false;
          })
        ];
      };

      # Bare metal configuration with rpool structure
      nixos-rpool = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          ./disko-config-rpool.nix
          baseConfig
          baremetalConfig
          ({config, ...}: {
            # Override networking to use different hostName for rpool
            networking.hostName = "with-rpool";
          })
        ];
      };

      # Removed Chaotic Nyx configurations
      nixos-dev-removed = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          baseConfig
          baremetalConfig
          ({
            config,
            lib,
            pkgs,
            ...
          }: {
            # Removed - was Chaotic configuration
          })
        ];
      };

      # QEMU/KVM configuration
      nixos-qemu = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          diskoConfig
          baseConfig
          qemuConfig
        ];
      };

      # QEMU/KVM Btrfs configuration with libre kernel
      nixos-qemu-btrfs = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          ./disko-config-btrfs.nix
          ./hardware-configuration-btrfs.nix
          baseConfig
          qemuConfig
          ({
            config,
            pkgs,
            ...
          }: {
            # Override kernel to use latest libre
            boot.kernelPackages = pkgs.linuxKernel.packages.linux_latest_libre;

            # QEMU-specific Btrfs optimizations
            boot.kernelParams = ["threadirqs" "mitigations=off"];

            # Use only free software
            nixpkgs.config.allowUnfree = false;
            hardware.enableRedistributableFirmware = false;
          })
        ];
      };

      # Media server configuration with Btrfs and arr stack
      nixos-media-server = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          ./disko-config-btrfs.nix
          ./hardware-configuration-btrfs.nix
          ./media-stack.nix
          baseConfig
          qemuConfig
          ({
            config,
            pkgs,
            ...
          }: {
            # Override kernel to use latest libre
            boot.kernelPackages = pkgs.linuxKernel.packages.linux_latest_libre;

            # Media server specific settings
            networking.hostName = "nixos-media";

            # Allow unfree for media codecs
            nixpkgs.config.allowUnfree = true;

            # Additional packages for media server
            environment.systemPackages = with pkgs; [
              docker
              docker-compose
              lazydocker
            ];

            # Enable Docker for additional services
            virtualisation.docker.enable = true;
            users.users.amoon.extraGroups = ["docker"];
          })
        ];
      };

      # Removed QEMU Chaotic configuration
      nixos-qemu-removed = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          baseConfig
          qemuConfig
          ({
            config,
            lib,
            pkgs,
            ...
          }: {
            # Removed - was Chaotic configuration
          })
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
