# NixOS Disko Multi-Host Setup

This repository provides a comprehensive, automated NixOS installation system using [disko](https://github.com/nix-community/disko) for disk partitioning and formatting. It supports multiple filesystem types, encryption, and automatic hardware detection.

## Features

### 🚀 **Automated Installation**
- **Interactive installer** with guided setup
- **Auto-detection** of suitable disks based on size, type (NVMe/SSD/HDD), and performance characteristics
- **Multiple filesystem support**: BTRFS (single/encrypted) and ZFS (single/mirror)
- **Partition labels** for reliable device identification
- **TPM2 auto-unlock** for encrypted systems with secure boot support

### 💾 **Disk Configurations**

| Configuration | Description | Use Case |
|---------------|-------------|----------|
| `btrfs-single` | Single disk BTRFS with subvolumes | Basic desktop/laptop |
| `btrfs-luks` | Encrypted BTRFS with TPM2 unlock | Secure workstation |
| `zfs-single` | Single disk ZFS with datasets | Performance-focused workstation |
| `zfs-mirror` | Two-disk ZFS mirror with redundancy | Critical data server |

### ⚡ **Performance Optimizations**

#### NVMe-Specific Optimizations
- **I/O Scheduler**: `none` for NVMe, `mq-deadline` for SATA SSD, `bfq` for HDD
- **Queue Depths**: Optimized for NVMe (2048 requests)
- **Polling**: Low-latency I/O polling for NVMe devices
- **TRIM**: Automatic TRIM/discard for all SSD types

#### Filesystem Optimizations
- **BTRFS**: `zstd:3` compression, async discard, autodefrag
- **ZFS**: Blake3 checksums, optimized ARC sizes, autotrim

#### System Performance
- **ZRAM**: 16GB compressed swap instead of disk swap
- **Kernel**: Latest kernel with performance tuning
- **Memory**: Optimized VM settings for SSD/NVMe workloads

### 🔧 **System Modules**

#### `modules/system/performance.nix`
- NVMe-specific kernel parameters and udev rules
- ZRAM swap configuration (16GB compressed)
- Network optimizations (BBR congestion control, CAKE qdisc)
- CPU performance tuning and mitigations control

#### `modules/system/boot.nix`
- Optimized initrd with essential modules
- Filesystem-specific boot optimizations
- TPM2 support for encryption
- Plymouth boot splash

#### `modules/system/maintenance.nix`
- Automated filesystem maintenance (scrub, balance, trim)
- Nix garbage collection and store optimization
- System health monitoring and alerting
- SMART disk monitoring

## Installation

### Prerequisites

1. **NixOS Live ISO** or existing NixOS system
2. **Internet connection** for downloading packages
3. **Target disk(s)** (⚠️ will be completely erased)

### Quick Start

```bash
# Clone the repository
git clone https://github.com/your-username/nixos-btrfs.git
cd nixos-btrfs

# Enter development shell
nix develop

# Run interactive installer
./scripts/install-interactive.sh
```

### Advanced Installation

#### Manual Disk Selection
```bash
# Install with specific disk
sudo nix run github:nix-community/disko#disko-install -- \
  --flake .#nixos \
  --disk main /dev/nvme0n1 \
  --write-efi-boot-entries
```

#### ZFS Mirror Installation
```bash
# For ZFS mirror configuration
sudo nix run github:nix-community/disko#disko-install -- \
  --flake .#server \
  --disk disk1 /dev/nvme0n1 \
  --disk disk2 /dev/nvme1n1 \
  --write-efi-boot-entries
```

#### Using Flake Apps
```bash
# Interactive installer
nix run .#install

# Direct disko install
nix run .#disko-install nixos /dev/nvme0n1

# Mount existing system for repair
sudo nix run .#mount
```

## Host Configuration

### Adding New Hosts

1. **Create host directory**:
   ```bash
   mkdir -p hosts/myhost
   ```

2. **Generate hardware configuration**:
   ```bash
   nixos-generate-config --root /mnt --dir hosts/myhost
   ```

3. **Create host configuration**:
   ```nix
   # hosts/myhost/configuration.nix
   { config, lib, pkgs, ... }:
   {
     # Host-specific settings
     time.timeZone = "America/New_York";
     
     # Enable specific services
     services.openssh.enable = true;
     
     # User configuration
     users.users.myuser = {
       isNormalUser = true;
       extraGroups = [ "wheel" ];
     };
   }
   ```

4. **Add to flake.nix**:
   ```nix
   nixosConfigurations = {
     myhost = mkSystem {
       hostname = "myhost";
       diskConfig = "btrfs-luks";  # or other config
       extraModules = [
         # Additional modules
       ];
     };
   };
   ```

### Disk Configuration Examples

#### Laptop with Single BTRFS
```nix
laptop = mkSystem {
  hostname = "laptop";
  diskConfig = "btrfs-single";
  extraModules = [
    nixos-hardware.nixosModules.common-laptop
    nixos-hardware.nixosModules.common-laptop-ssd
    {
      # Laptop-specific optimizations
      system.performance.zramSwap.memoryPercent = 75;
      services.thermald.enable = true;
    }
  ];
};
```

#### Server with ZFS Mirror
```nix
server = mkSystem {
  hostname = "server";
  diskConfig = "zfs-mirror";
  extraModules = [
    {
      services.openssh.enable = true;
      services.zfs.autoSnapshot.enable = true;
      
      # Server-specific ZFS tuning
      boot.kernelParams = [
        "zfs.zfs_arc_max=32212254720"  # 30GB for server
      ];
    }
  ];
};
```

### Auto-Detection Override

Override disk detection per host:

```nix
# hosts/myhost/configuration.nix
{
  # Override auto-detected disk
  disko.primaryDisk = "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_...";
  
  # For ZFS mirror, override both disks
  disko.mirrorDisks = [
    "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_1"
    "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_2"
  ];
}
```

## Post-Installation

### Initial Setup

1. **Reboot into new system**:
   ```bash
   sudo reboot
   ```

2. **Set user password**:
   ```bash
   passwd yourusername
   ```

3. **Enable TPM2 auto-unlock** (for encrypted systems):
   ```bash
   setup-tpm2-luks
   ```

4. **Update system**:
   ```bash
   sudo nixos-rebuild switch --flake /etc/nixos#hostname
   ```

### System Maintenance

The system includes automated maintenance tasks:

- **Daily**: System health checks, log rotation
- **Weekly**: Filesystem balance/scrub, package cleanup
- **Monthly**: Deep filesystem maintenance, system optimization

#### Manual Maintenance Commands

```bash
# Check filesystem health
sudo btrfs filesystem show
sudo btrfs scrub status /

# Check ZFS health  
sudo zpool status -v
sudo zfs list

# System health overview
systemctl status *maintenance*
journalctl -u system-maintenance
```

### Performance Monitoring

```bash
# Check NVMe performance
sudo iotop -a
sudo nvme smart-log /dev/nvme0n1

# Monitor filesystem performance
sudo btrfs filesystem usage /
sudo zpool iostat -v 1

# System performance
btop
sudo smartctl -a /dev/nvme0n1
```

## Troubleshooting

### Installation Issues

#### Disk Detection Problems
```bash
# List all disks
lsblk -f

# Check disk health
sudo smartctl -a /dev/nvme0n1

# Manual disk selection
sudo nix run .#disko-install nixos /dev/specific-disk
```

#### LUKS Encryption Issues
```bash
# Check LUKS status
sudo cryptsetup status root

# Manual unlock
sudo cryptsetup open /dev/disk/by-partlabel/cryptroot root

# Reset TPM2 enrollment
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/disk/by-partlabel/cryptroot
sudo systemd-cryptenroll --tpm2-device=auto /dev/disk/by-partlabel/cryptroot
```

### Boot Issues

#### Mount Existing System
```bash
# Use the mount script
sudo ./scripts/mount-system.sh

# Manual mount for BTRFS
sudo mount -o subvol=@ /dev/mapper/root /mnt
sudo mount -o subvol=@home /dev/mapper/root /mnt/home
sudo mount /dev/disk/by-partlabel/ESP /mnt/boot

# Chroot and fix
sudo chroot /mnt
```

#### ZFS Import Issues
```bash
# Force import pools
sudo zpool import -f rpool

# Check pool status
sudo zpool status

# Mount datasets
sudo zfs mount -a
```

### Performance Issues

#### NVMe Not Detected as SSD
```bash
# Check if NVMe is detected as rotational
cat /sys/block/nvme0n1/queue/rotational

# Should be 0 for NVMe/SSD, 1 for HDD
```

#### Filesystem Performance
```bash
# BTRFS defrag
sudo btrfs filesystem defragment -r -czstd /home

# ZFS performance tuning
echo 8589934592 | sudo tee /sys/module/zfs/parameters/zfs_arc_max
```

## Development

### Project Structure

```
├── flake.nix                    # Main flake configuration
├── lib/
│   └── disk-detection.nix       # Disk auto-detection utilities
├── modules/
│   ├── disko/                   # Disk configurations
│   │   ├── btrfs-single.nix
│   │   ├── btrfs-luks.nix
│   │   ├── zfs-single.nix
│   │   └── zfs-mirror.nix
│   └── system/                  # System modules
│       ├── performance.nix      # Performance optimizations
│       ├── boot.nix            # Boot configuration
│       └── maintenance.nix     # Maintenance tasks
├── hosts/                       # Per-host configurations
│   └── nixos/
├── scripts/                     # Installation and utility scripts
│   ├── install-interactive.sh   # Interactive installer
│   └── mount-system.sh         # System mount tool
└── README.md
```

### Testing

```bash
# Test in VM
nix run .#run-vm

# Test configuration without installation
nix flake check

# Test specific host
nix build .#nixosConfigurations.hostname.config.system.build.toplevel
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Test your changes in a VM
4. Submit a pull request

## References

- [Disko Documentation](https://github.com/nix-community/disko)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [ZFS on NixOS](https://nixos.wiki/wiki/ZFS)
- [BTRFS on NixOS](https://nixos.wiki/wiki/Btrfs)
- [Lanzaboote Secure Boot](https://github.com/nix-community/lanzaboote)

---

**⚠️ Warning**: This setup will completely erase the target disk(s). Always backup important data before installation.

**💡 Tip**: Use the interactive installer for the best experience, especially when setting up for the first time.