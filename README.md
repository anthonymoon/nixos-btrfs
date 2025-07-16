# NixOS ZFS Installation Flake

A comprehensive NixOS flake that provides ZFS-based installations with deduplication, multi-platform support, gaming optimizations via Chaotic Nyx, and a complete desktop environment.

## 🚀 Quick Start

### One-Line Installation
```bash
# Boot from NixOS ISO, then:
nix run github:yourusername/nixos-config#install-script
```

### Manual Deployment
```bash
# Clone the repository
git clone https://github.com/yourusername/nixos-config.git
cd nixos-config

# Deploy to system (auto-detects platform and disk)
nix run .#deploy

# Or specify disk and platform
nix run .#deploy /dev/sda baremetal
```

## 📦 Build Outputs

### ISO Image
```bash
# Build bootable ISO
nix build .#iso
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress

# The ISO includes the installer script pre-configured
```

### Virtual Machine Images
```bash
# QEMU/KVM image
nix build .#qemu-image

# HyperV image
nix build .#hyperv-image

# Run QEMU VM
nix run .#run-qemu
```

## 🏗️ Architecture

### ZFS Layout
```
zroot (pool)
├── root      → /         (LZ4 compression)
├── home      → /home     (ZSTD-3, 1M recordsize)
├── nix       → /nix      (ZSTD-6 + deduplication, 64K recordsize)
├── persist   → /persist  (LZ4 compression)
├── var       → /var      (LZ4 compression)
├── var/log   → /var/log  (GZIP compression, 128K recordsize)
└── reserved              (10GB reserved space)
```

### Features
- **ZFS deduplication** on `/nix` for 60-80% space savings
- **Multi-platform support** (bare metal, QEMU, HyperV)
- **Automatic disk detection** (sda/vda/nvme)
- **16GB ZRAM swap** with zstd compression
- **Hyprland desktop** with Waybar and modern tools
- **Gaming optimized** with Chaotic Nyx (Mesa-git, GameMode, MangoHud)
- **Performance enhanced** with SCX scheduler and optimizations
- **Development environment** with VS Code and tools

## 🎯 Platform Configurations

### Bare Metal (`nixos-dev`)
- Full hardware acceleration
- AMDGPU support
- Optimal ZFS performance

### QEMU/KVM (`nixos-qemu`)
- VirtIO drivers
- SPICE integration
- Guest agent support

### HyperV (`nixos-hyperv`)
- Enhanced session mode
- Dynamic resolution
- Integration services

## 📝 Configuration

### User Configuration
- **User**: amoon (Anthony Moon)
- **Email**: anthony@dirtybit.co
- **Shell**: Fish with Starship prompt
- **Desktop**: Hyprland with Waybar

### Network
- **Manager**: systemd-networkd
- **DHCP**: Enabled on all interfaces
- **DNS**: AdGuard (94.140.14.14, 94.140.15.15)

### ZFS Settings
- **ARC Memory**: 2-8GB (auto-tuned based on RAM)
- **Deduplication**: Enabled on `/nix` only
- **Compression**: Tiered (LZ4/ZSTD-3/ZSTD-6)
- **Auto-scrub**: Weekly
- **Auto-snapshot**: Enabled

## 🛠️ Development

### Development Shell
```bash
nix develop
```

Provides:
- NixOS rebuild tools
- QEMU for testing
- ZFS utilities
- Development tools

### Available Commands
```bash
# Build outputs
nix build .#iso
nix build .#qemu-image
nix build .#hyperv-image

# Deploy/install
nix run .#deploy
nix run .#install-script

# Run VM
nix run .#run-qemu
```

## 🔧 Customization

### Modify User Settings
Edit `home.nix` to customize:
- Shell aliases and configuration
- Hyprland keybindings
- Application preferences
- Development tools

### Modify System Settings
Edit `flake.nix` to customize:
- System packages
- Hardware configuration
- ZFS settings
- Platform-specific optimizations

### Modify Disk Layout
Edit `disko-config.nix` to customize:
- Partition sizes
- ZFS dataset structure
- Compression algorithms
- Mount options

## 📊 Performance

### Expected Results
- **Boot time**: ~10 seconds
- **Desktop launch**: ~2 seconds
- **Storage efficiency**: 60-80% space savings on `/nix`
- **Memory usage**: ~1.5GB idle with Hyprland
- **Game performance**: Near native with Proton

### ZFS Monitoring
```bash
# Pool status
zpool status -D

# Deduplication ratio
zpool list -o name,dedup,health

# Dataset usage
zfs list -o name,used,compressratio,dedup

# ARC statistics
arc_summary
```

## 🆘 Troubleshooting

### Common Issues

**Installation fails with ZFS error**
```bash
# Check if ZFS modules are loaded
lsmod | grep zfs

# Force import pool
zpool import -f zroot
```

**Low dedup ratio**
- Dedup needs time to analyze data
- Check after installing packages: `zpool get dedupratio zroot`

**Boot issues**
- Verify host ID: `head -c 8 /etc/machine-id`
- Check ZFS import: `zpool import`

### Recovery
```bash
# Boot from NixOS ISO
# Import pool
zpool import -f zroot

# Mount filesystems
mount -t zfs zroot/root /mnt
mount -t zfs zroot/home /mnt/home
mount -t zfs zroot/nix /mnt/nix
mount /dev/disk/by-label/BOOT /mnt/boot

# Rebuild system
nixos-rebuild switch --flake /mnt/etc/nixos#nixos-dev
```

## 📋 System Requirements

- **RAM**: Minimum 4GB (8GB+ recommended for optimal ZFS performance)
- **Disk**: Minimum 20GB (64GB+ recommended)
- **UEFI**: Required for boot
- **Internet**: Required for initial installation

## 🔐 Security

- Default passwords disabled
- User setup required on first boot
- Secure boot compatible
- ZFS encryption ready (disabled by default)

## 🎮 Gaming

Enhanced gaming stack with Chaotic Nyx:
- **Steam** with Proton support
- **Lutris** for non-Steam games  
- **Wine** with dependencies
- **Discord** for communication
- **GameMode** for automatic game optimizations
- **MangoHud** for performance monitoring
- **Mesa-git** for latest graphics drivers
- **SCX scheduler** for better CPU scheduling
- Hardware acceleration with latest drivers

## 📄 License

This configuration is provided as-is for educational and personal use. Modify as needed for your requirements.

---

**Note**: Replace `yourusername/nixos-config` with your actual GitHub repository URL in all commands and configuration files.