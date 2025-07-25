# NixOS Configuration

A modular NixOS configuration following community standards with comprehensive system support.

## Features

- **Filesystem**: Btrfs with optimized subvolumes and compression
- **Kernel**: Linux (latest)
- **Desktop**: Hyprland with Waybar
- **Services**: Complete media automation stack (Jellyfin, *arr services, Traefik)
- **Gaming**: Steam, Proton, controller support, NVIDIA/AMD GPU drivers
- **Development**: Multiple languages, cloud tools, editors
- **Virtualization**: QEMU/KVM and Hyper-V optimization
- **Multi-filesystem**: Support for NTFS, APFS, XFS, exFAT, Btrfs

## Structure

```
.
├── config/          # User configuration files
├── flake.nix        # Main flake configuration
├── home.nix         # Home Manager configuration  
├── hosts/           # Host-specific configurations
│   └── nixos/       # Single host configuration
├── lib/             # Helper functions
├── modules/         # NixOS modules
│   ├── core.nix
│   ├── desktop.nix
│   ├── development.nix
│   ├── filesystems.nix
│   ├── gaming.nix
│   ├── media-server.nix
│   ├── networking.nix
│   ├── nix-config.nix
│   └── virtualization.nix
├── overlays/        # Package overlays
└── packages/        # Modular package lists
```

## Installation

### Quick Install (from NixOS LiveCD)

**Note**: Run as root user (no sudo needed in LiveCD)

```bash
# Automagic VM deployer - one command does it all (RECOMMENDED)
# For BTRFS VM:
nix run \
  --extra-experimental-features nix-command \
  --extra-experimental-features flakes \
  github:anthonymoon/nixos-btrfs#deploy-vm -- /dev/sda vm

# For ZFS VM (auto-detects and handles NIXPKGS_ALLOW_BROKEN):
nix run \
  --extra-experimental-features nix-command \
  --extra-experimental-features flakes \
  github:anthonymoon/nixos-btrfs#deploy-vm -- /dev/sda vm-zfs

# Fully automated (skip confirmation, auto-reboot):
nix run \
  --extra-experimental-features nix-command \
  --extra-experimental-features flakes \
  github:anthonymoon/nixos-btrfs#deploy-vm -- /dev/sda vm --auto

# Standard disko installer (if smart-install fails)
nix run \
  --extra-experimental-features nix-command \
  --extra-experimental-features flakes \
  github:anthonymoon/nixos-btrfs#disko-install -- vm /dev/sda

# For ZFS with disko-install
NIXPKGS_ALLOW_BROKEN=1 nix run \
  --extra-experimental-features nix-command \
  --extra-experimental-features flakes \
  --impure \
  github:anthonymoon/nixos-btrfs#disko-install -- vm-zfs /dev/sda
```

Available hosts:
- `vm` - Minimal VM with BTRFS (supports QEMU/KVM and Hyper-V)
- `vm-zfs` - Minimal VM with ZFS (supports QEMU/KVM and Hyper-V)
- `nixos` - Full desktop system with BTRFS+LUKS encryption

### Deploy-VM Options

The `deploy-vm` script supports automation flags:

```bash
# Options:
#   -y, --auto-accept    Auto-accept disk wipe confirmation
#   -r, --auto-reboot    Auto-reboot after installation
#   -a, --auto           Enable both auto-accept and auto-reboot
#   -h, --help           Show help message

# Examples:
nix run github:anthonymoon/nixos-btrfs#deploy-vm -- /dev/sda vm --auto-accept
nix run github:anthonymoon/nixos-btrfs#deploy-vm -- /dev/sda vm --auto-reboot  
nix run github:anthonymoon/nixos-btrfs#deploy-vm -- /dev/sda vm --auto
```

### VM Platform Support

The VM configurations include optimizations for multiple virtualization platforms:

**QEMU/KVM:**
- QEMU guest agent for host integration
- VirtIO optimizations
- Serial console support

**Hyper-V:**
- Hyper-V kernel modules (hv_vmbus, hv_balloon, hv_storvsc, hv_netvsc)
- Hyper-V guest services (file copy, key-value pairs, VSS)
- Enhanced session mode support
- Automatic detection and loading

**Both platforms:**
- UEFI boot support with variable modification
- Optimized for headless operation
- SSH enabled by default
- Serial console access

### Manual Install

```bash
# Partition and format
nix run github:nix-community/disko -- \
  --mode disko \
  --flake github:anthonymoon/nixos-btrfs#nixos

# Install
nixos-install --flake github:anthonymoon/nixos-btrfs#nixos
```

## Disk Layout (Btrfs)

```
/dev/sda
├── /boot     (1GB, ESP, FAT32)
├── swap      (16GB)
└── /         (Btrfs with subvolumes)
    ├── @         → /         (zstd:3)
    ├── @home     → /home     (zstd:3)
    ├── @nix      → /nix      (zstd:6)
    ├── @var      → /var      (zstd:3)
    ├── @tmp      → /tmp      (zstd:1)
    └── @snapshots → /.snapshots (zstd:3)
```

## Usage

### Local System
```bash
# Rebuild current system
sudo nixos-rebuild switch --flake .#nixos

# Test changes without switching
sudo nixos-rebuild test --flake .#nixos
```

### Remote System
```bash
# Deploy to remote host
sudo nixos-rebuild switch --flake .#nixos --target-host amoon@deadbeef.dirtybit.co

# Build locally, deploy remotely
sudo nixos-rebuild switch --flake .#nixos --target-host amoon@deadbeef.dirtybit.co --build-host localhost
```

### Maintenance
```bash
# Update flake inputs
nix flake update

# Check flake
nix flake check

# Format code
nix fmt

# Development shell
nix develop
```

### Building Images
```bash
# Build ISO installer
nix build .#iso
# Result: result/iso/*.iso

# Build QEMU VM (for testing)
nix build .#vm
# Run with: ./result/bin/run-nixos-vm

# Quick VM test
nix run .#run-vm

# Build QEMU disk image (qcow2)
nix build .#qemu-image
# Result: result/*.qcow2

# Build Hyper-V image (VHDX)
nix build .#hyperv-image
# Result: result/*.vhdx
```

## Configuration Details

- **Hostname**: deadbeef
- **Domain**: dirtybit.co
- **User**: amoon
- **Timezone**: UTC
- **Shell**: Fish with Starship
- **Desktop**: Hyprland

## Services

### Media Server
- Jellyfin (port 8096)
- Radarr, Sonarr, Prowlarr, Bazarr, Lidarr, Readarr
- Jellyseerr (port 5055)
- Transmission
- AdGuard Home (port 3000)
- Samba & NFS
- Traefik reverse proxy

### Development
- Docker with Btrfs storage driver
- Multiple language support (Python 3.12, Node.js 22, Go, Rust)
- Cloud tools (Terraform, gcloud, AWS CLI, Azure CLI)
- VS Code, Neovim

### Gaming
- Steam with Proton GE
- GameMode
- MangoHud & GOverlay
- Controller support (Xbox, PlayStation)
- NVIDIA proprietary drivers
- AMD GPU support

## Network

- systemd-networkd (no NetworkManager)
- AdGuard DNS (94.140.14.14, 94.140.15.15)
- Firewall enabled with service-specific ports

## Performance

- ZRAM swap (100% memory, zstd)
- Btrfs with compression and async discard
- Weekly garbage collection
- Nix store optimization
- Cachix binary caches

## Monitoring

```bash
# Btrfs status
sudo btrfs filesystem show
sudo btrfs filesystem df /

# System resources
btop

# Gaming performance
mangohud <game>

# Docker
docker ps
docker stats
```

## Troubleshooting

### Rebuild fails
```bash
# Check flake
nix flake check

# Verbose rebuild
sudo nixos-rebuild switch --flake .#nixos --show-trace
```

### Disk space
```bash
# Check Btrfs usage
sudo compsize /
sudo btrfs filesystem usage /

# Clean old generations
sudo nix-collect-garbage -d
```

### Services
```bash
# Check service status
systemctl status jellyfin
systemctl status docker

# View logs
journalctl -u jellyfin -f
```

## License

This configuration is provided as-is for personal use.