#!/usr/bin/env bash
set -euo pipefail

# Minimal NixOS installer - partitions first, then installs
# This avoids space issues on live ISOs

HOST="${1:-vm}"
DISK="${2:-/dev/sda}"

echo "Minimal NixOS Installer"
echo "======================"
echo "Host: $HOST"
echo "Disk: $DISK"
echo ""

# Warning
echo "WARNING: This will COMPLETELY ERASE $DISK"
read -p "Continue? (yes/NO): " confirm
[[ "$confirm" != "yes" ]] && exit 0

# Step 1: Create minimal partition layout manually
echo "Creating partitions..."

# Wipe the disk
dd if=/dev/zero of="$DISK" bs=1M count=100 status=progress || true
sync

# Create GPT partition table
parted -s "$DISK" mklabel gpt

# Create boot partition (1GB)
parted -s "$DISK" mkpart ESP fat32 1MiB 1GiB
parted -s "$DISK" set 1 esp on

# Create root partition (rest of disk)
parted -s "$DISK" mkpart primary btrfs 1GiB 100%

# Wait for partitions to appear
sleep 2
partprobe "$DISK"
sleep 2

# Format partitions
echo "Formatting partitions..."
mkfs.fat -F32 -n BOOT "${DISK}1"
mkfs.btrfs -f -L nixos "${DISK}2"

# Mount partitions
echo "Mounting partitions..."
mount "${DISK}2" /mnt

# Create BTRFS subvolumes
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@tmp
btrfs subvolume create /mnt/@var

# Unmount and remount with subvolumes
umount /mnt

# Mount root subvolume
mount -o compress=zstd:3,noatime,subvol=@ "${DISK}2" /mnt

# Create mount points
mkdir -p /mnt/{boot,home,nix,tmp,var}

# Mount boot
mount "${DISK}1" /mnt/boot

# Mount other subvolumes
mount -o compress=zstd:3,noatime,subvol=@home "${DISK}2" /mnt/home
mount -o compress=zstd:6,noatime,subvol=@nix "${DISK}2" /mnt/nix
mount -o compress=zstd:1,noatime,subvol=@tmp "${DISK}2" /mnt/tmp
mount -o compress=zstd:3,noatime,subvol=@var "${DISK}2" /mnt/var

# Step 2: Generate minimal hardware config
echo "Generating hardware configuration..."
nixos-generate-config --root /mnt

# Step 3: Install NixOS
echo "Installing NixOS..."
nixos-install \
  --root /mnt \
  --no-root-password \
  --flake "github:anthonymoon/nixos-btrfs#$HOST" \
  --max-jobs 2 \
  --option substituters "https://cache.nixos.org" \
  --option trusted-public-keys "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" \
  --option narinfo-cache-negative-ttl 0 \
  --show-trace

echo ""
echo "Installation complete!"
echo "1. Reboot: reboot"
echo "2. Login as 'amoon' with password 'nixos'"
echo "3. Change your password: passwd"