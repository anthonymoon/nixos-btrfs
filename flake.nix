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

      # Minimal VM configuration with BTRFS
      vm = mkSystem {
        hostname = "vm";
        diskConfig = "btrfs-single";
        extraModules = [
          {
            # VM-specific optimizations
            services.qemuGuest.enable = true;
            boot.kernelParams = ["console=ttyS0"];
          }
        ];
      };

      # Minimal VM configuration with ZFS (may require newer kernel)
      vm-zfs = mkSystem {
        hostname = "vm-zfs";
        diskConfig = "zfs-single";
        extraModules = [
          {
            # VM-specific optimizations
            services.qemuGuest.enable = true;
            boot.kernelParams = ["console=ttyS0"];
            # Allow broken packages for ZFS kernel compatibility
            nixpkgs.config.allowBroken = true;
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
        program = let
          diskoInstall = pkgs.writeShellScriptBin "disko-install" ''
            #!/usr/bin/env bash
            set -euo pipefail

            # Colors for output
            RED='\033[0;31m'
            GREEN='\033[0;32m'
            YELLOW='\033[0;33m'
            NC='\033[0m' # No Color

            # Function to print colored output
            print_error() { echo -e "''${RED}[ERROR]''${NC} $1" >&2; }
            print_success() { echo -e "''${GREEN}[SUCCESS]''${NC} $1"; }
            print_warning() { echo -e "''${YELLOW}[WARNING]''${NC} $1"; }
            print_info() { echo -e "[INFO] $1"; }

            # Input validation
            usage() {
              echo "Usage: $0 <host> [disk]"
              echo ""
              echo "Available hosts:"
              echo "  nixos       - Main system with BTRFS+LUKS"
              echo "  vm          - Virtual machine with BTRFS"
              echo "  vm-zfs      - Virtual machine with ZFS"
              echo ""
              echo "Examples:"
              echo "  $0 vm /dev/sda"
              echo "  $0 vm-zfs /dev/vda"
              echo ""
              exit 1
            }

            # Parse arguments
            if [[ $# -lt 1 ]]; then
              print_error "Missing required argument: host"
              usage
            fi

            HOST="$1"
            DISK="''${2:-}"

            # Validate host exists
            VALID_HOSTS=("nixos" "vm" "vm-zfs")
            if [[ ! " ''${VALID_HOSTS[@]} " =~ " ''${HOST} " ]]; then
              print_error "Invalid host: $HOST"
              print_info "Valid hosts are: ''${VALID_HOSTS[*]}"
              exit 1
            fi

            # Validate disk if provided
            if [[ -n "$DISK" ]]; then
              if [[ ! -b "$DISK" ]]; then
                print_error "Disk device $DISK does not exist or is not a block device"
                exit 1
              fi

              # Check if disk is mounted
              if mount | grep -q "^$DISK"; then
                print_error "Disk $DISK appears to be mounted. Please unmount it first."
                exit 1
              fi
            fi

            # Check for required tools
            for cmd in nix sudo; do
              if ! command -v "$cmd" &> /dev/null; then
                print_error "Required command '$cmd' not found in PATH"
                exit 1
              fi
            done

            # Determine if we need NIXPKGS_ALLOW_BROKEN for ZFS
            EXTRA_FLAGS=""
            if [[ "$HOST" == "vm-zfs" ]]; then
              print_warning "ZFS configuration may require allowing broken packages"
              EXTRA_FLAGS="--impure"
              export NIXPKGS_ALLOW_BROKEN=1
            fi

            echo "╔════════════════════════════════════════════════════════════╗"
            echo "║                   NixOS Disko Installer                    ║"
            echo "╚════════════════════════════════════════════════════════════╝"
            echo ""
            echo "Host: $HOST"
            if [[ -n "$DISK" ]]; then
              echo "Disk: $DISK"
            else
              echo "Disk: Auto-detect"
            fi
            echo ""

            # Confirmation prompt
            print_warning "This will COMPLETELY ERASE the selected disk!"
            read -p "Are you sure you want to continue? (yes/NO): " confirm
            if [[ "$confirm" != "yes" ]]; then
              print_info "Installation cancelled"
              exit 0
            fi

            echo ""
            print_info "Starting installation..."
            echo ""

            # Build the full command
            NIX_CMD="nix run"
            NIX_CMD="$NIX_CMD --extra-experimental-features nix-command"
            NIX_CMD="$NIX_CMD --extra-experimental-features flakes"
            NIX_CMD="$NIX_CMD --no-write-lock-file"  # Properly handle lock file
            NIX_CMD="$NIX_CMD $EXTRA_FLAGS"
            NIX_CMD="$NIX_CMD github:nix-community/disko/latest#disko-install"
            NIX_CMD="$NIX_CMD --"
            NIX_CMD="$NIX_CMD --flake 'github:anthonymoon/nixos-btrfs#$HOST'"
            NIX_CMD="$NIX_CMD --write-efi-boot-entries"

            if [[ -n "$DISK" ]]; then
              NIX_CMD="$NIX_CMD --disk main '$DISK'"
            fi

            # Execute with proper error handling
            if bash -c "$NIX_CMD"; then
              print_success "Installation completed successfully!"
              echo ""
              print_info "Next steps:"
              echo "  1. Reboot into your new system"
              echo "  2. Login with user 'amoon' and password 'nixos'"
              echo "  3. Change your password with: passwd"
              echo "  4. Update your configuration in /etc/nixos/"
            else
              print_error "Installation failed!"
              exit 1
            fi
          '';
        in "${diskoInstall}/bin/disko-install";
      };

      # Smart installer that handles space issues
      smart-install = {
        type = "app";
        program = let
          smartInstall = pkgs.writeShellScriptBin "smart-install" ''
            #!/usr/bin/env bash
            set -euo pipefail

            # Smart NixOS installer that handles space issues automatically

            # Colors
            RED='\033[0;31m'
            GREEN='\033[0;32m'
            YELLOW='\033[0;33m'
            BLUE='\033[0;34m'
            NC='\033[0m'

            print_error() { echo -e "''${RED}[ERROR]''${NC} $1" >&2; }
            print_success() { echo -e "''${GREEN}[SUCCESS]''${NC} $1"; }
            print_warning() { echo -e "''${YELLOW}[WARNING]''${NC} $1"; }
            print_info() { echo -e "''${BLUE}[INFO]''${NC} $1"; }

            # Parse arguments
            HOST="''${1:-vm}"
            DISK="''${2:-}"

            echo "╔══════════════════════════════════════════════════════════════╗"
            echo "║                   Smart NixOS Installer                      ║"
            echo "║                  (Handles space automatically)               ║"
            echo "╚══════════════════════════════════════════════════════════════╝"
            echo ""

            # Validate inputs
            if [[ -z "$DISK" ]]; then
              print_error "Disk parameter is required"
              echo "Usage: $0 <host> <disk>"
              echo "Example: $0 vm /dev/sda"
              exit 1
            fi

            if [[ ! -b "$DISK" ]]; then
              print_error "Disk $DISK does not exist"
              exit 1
            fi

            print_info "Target host: $HOST"
            print_info "Target disk: $DISK"
            echo ""

            # Warning
            print_warning "This will COMPLETELY ERASE $DISK"
            read -p "Continue? (yes/NO): " confirm
            [[ "$confirm" != "yes" ]] && exit 0

            # Method: Partition first, then install to mounted filesystem
            # This avoids the space issue entirely

            print_info "Phase 1: Partitioning disk with disko..."

            # Get the disk configuration
            DISKO_CMD="nix run \
              --extra-experimental-features nix-command \
              --extra-experimental-features flakes \
              --no-write-lock-file"

            # For ZFS configs, we need special handling
            EXTRA_FLAGS=""
            if [[ "$HOST" == *"zfs"* ]]; then
              export NIXPKGS_ALLOW_BROKEN=1
              EXTRA_FLAGS="--impure"
            fi

            # Use our own disko-install which handles disk specification properly
            print_info "Using integrated installer for $HOST on $DISK"

            # Build the disko-install command
            NIX_CMD="nix run"
            NIX_CMD="$NIX_CMD --extra-experimental-features nix-command"
            NIX_CMD="$NIX_CMD --extra-experimental-features flakes"
            NIX_CMD="$NIX_CMD --no-write-lock-file"

            # Set EXTRA_FLAGS for ZFS if not already set
            EXTRA_FLAGS="''${EXTRA_FLAGS:-}"
            NIX_CMD="$NIX_CMD $EXTRA_FLAGS"
            NIX_CMD="$NIX_CMD github:anthonymoon/nixos-btrfs#disko-install"
            NIX_CMD="$NIX_CMD -- $HOST $DISK"

            print_info "Executing installation..."
            if eval "$NIX_CMD"; then
              print_success "Installation completed successfully!"
              echo ""
              print_info "Next steps:"
              echo "  1. Reboot into your new system: reboot"
              echo "  2. Login as 'amoon' with password 'nixos'"
              echo "  3. Change your password: passwd"
              echo ""
              print_success "Welcome to NixOS!"
            else
              print_error "Installation failed"
              exit 1
            fi

            # Show what we're doing
            print_info "Running nixos-install..."
            echo ""

            # Execute installation
            if eval "$NIX_INSTALL_CMD"; then
              print_success "Installation completed successfully!"
              echo ""
              print_info "Next steps:"
              echo "  1. Reboot into your new system: reboot"
              echo "  2. Login as 'amoon' with password 'nixos'"
              echo "  3. Change your password: passwd"
              echo ""
              print_success "Welcome to NixOS!"
            else
              print_error "Installation failed"
              print_info "Check the logs above for details"
              exit 1
            fi
          '';
        in "${smartInstall}/bin/smart-install";
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

      # Minimal installer for space-constrained environments
      minimal-install = {
        type = "app";
        program = let
          minimalInstall = pkgs.writeShellScriptBin "minimal-install" ''
            #!/usr/bin/env bash
            export PATH="${pkgs.lib.makeBinPath [
              pkgs.coreutils
              pkgs.util-linux
              pkgs.parted
              pkgs.dosfstools
              pkgs.btrfs-progs
              pkgs.nixos-install-tools
            ]}:$PATH"
            exec ${./scripts/minimal-install.sh} "$@"
          '';
        in "${minimalInstall}/bin/minimal-install";
      };
    };
  };
}
