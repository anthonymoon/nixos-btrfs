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

```bash
# Install with flake (requires experimental features)
sudo nix --extra-experimental-features "nix-command flakes" run github:anthonymoon/nixos-btrfs#install

# Or use curl installer
curl -sL https://raw.githubusercontent.com/anthonymoon/nixos-btrfs/main/install.sh | sudo bash

# Specify different disk (default is /dev/sda)
sudo nix --extra-experimental-features "nix-command flakes" run github:anthonymoon/nixos-btrfs#install -- /dev/nvme0n1
```

### Manual Install

```bash
# Partition and format
sudo nix run github:nix-community/disko -- --mode disko --flake github:anthonymoon/nixos-btrfs#nixos

# Install
sudo nixos-install --flake github:anthonymoon/nixos-btrfs#nixos
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