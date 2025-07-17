#!/usr/bin/env bash
set -euo pipefail

# Simple disk formatter and mounter for NixOS installation

DISK="${1:-/dev/sda}"

echo "NixOS Disk Formatter"
echo "==================="
echo "Disk: $DISK"
echo ""

# Warning
echo "WARNING: This will COMPLETELY ERASE $DISK"
read -p "Continue? (yes/NO): " confirm
[[ "$confirm" != "yes" ]] && exit 0

# Wipe and partition
echo "Creating partitions..."
dd if=/dev/zero of="$DISK" bs=1M count=100 status=progress || true
sync

parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 1GiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary btrfs 1GiB 100%

sleep 2
partprobe "$DISK"
sleep 2

# Format
echo "Formatting..."
mkfs.fat -F32 -n BOOT "${DISK}1"
mkfs.btrfs -f -L nixos "${DISK}2"

# Mount and create subvolumes
echo "Creating BTRFS subvolumes..."
mount "${DISK}2" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@tmp
btrfs subvolume create /mnt/@var
umount /mnt

# Mount everything properly
echo "Mounting filesystems..."
mount -o compress=zstd:3,noatime,subvol=@ "${DISK}2" /mnt

mkdir -p /mnt/{boot,home,nix,tmp,var}

mount "${DISK}1" /mnt/boot
mount -o compress=zstd:3,noatime,subvol=@home "${DISK}2" /mnt/home
mount -o compress=zstd:6,noatime,subvol=@nix "${DISK}2" /mnt/nix
mount -o compress=zstd:1,noatime,subvol=@tmp "${DISK}2" /mnt/tmp
mount -o compress=zstd:3,noatime,subvol=@var "${DISK}2" /mnt/var

echo ""
echo "Disk formatted and mounted at /mnt"
echo ""
echo "Next steps:"
echo "1. Generate config: nixos-generate-config --root /mnt"
echo "2. Install: nixos-install --root /mnt --flake github:anthonymoon/nixos-btrfs#vm"
echo ""
echo "Or for ZFS:"
echo "NIXPKGS_ALLOW_BROKEN=1 nixos-install --root /mnt --flake github:anthonymoon/nixos-btrfs#vm-zfs --impure"