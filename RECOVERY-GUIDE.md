# ZFS Boot Recovery Guide

## Quick Fix from NixOS Installer

If your system hangs with "still waiting for zroot", follow these steps:

### 1. Boot from NixOS Installer ISO
- Use a NixOS installer ISO with ZFS support
- Boot into the live environment

### 2. Import ZFS Pool
```bash
# Load ZFS kernel module
sudo modprobe zfs

# Import the pool
sudo zpool import -f zroot

# Check pool status
sudo zpool status
```

### 3. Mount Filesystems
```bash
# Create mount point
sudo mkdir -p /mnt

# Mount root filesystem
sudo mount -t zfs zroot/root/nixos /mnt

# Mount other filesystems
sudo mkdir -p /mnt/{boot,home,nix,persist}
sudo mount -t zfs zroot/home /mnt/home
sudo mount -t zfs zroot/nix /mnt/nix
sudo mount -t zfs zroot/persist /mnt/persist

# Mount boot partition (adjust device as needed)
# Find your ESP partition with: lsblk -f
sudo mount /dev/sda1 /mnt/boot  # or /dev/nvme0n1p1, etc.
```

### 4. Get Updated Configuration
```bash
# Option A: If you have internet, get the latest fix
cd /mnt/home/amoon
git clone https://github.com/anthonymoon/nixos-zfsroot.git refactor-new
cd refactor-new

# Option B: Use existing configuration
cd /mnt/home/amoon/refactor
```

### 5. Rebuild System
```bash
# Rebuild with the fixed configuration
sudo nixos-install --flake .#nixos-dev --no-root-passwd
```

### 6. Cleanup and Reboot
```bash
# Unmount everything
sudo umount -R /mnt

# Export pool
sudo zpool export zroot

# Reboot
sudo reboot
```

## What Was Fixed

The configuration was updated to:
1. Set `boot.zfs.forceImportRoot = true` to ensure the pool imports at boot
2. Fixed root dataset mount configuration
3. Added explicit filesystem mount entry for root with `zfsutil` option

## If Issues Persist

Check that:
- Your disk device path is correct in the flake configuration
- The hostId is set (it's currently "abcd1234" - you may want to generate a unique one)
- All ZFS datasets exist: `zfs list -r zroot`

## Generate Unique Host ID

```bash
# Generate a random 8-character hex hostId
head -c4 /dev/urandom | od -A none -t x4 | sed 's/ //'
```

Then update the `networking.hostId` in flake.nix with this value.