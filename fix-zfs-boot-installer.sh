#!/usr/bin/env bash
set -euo pipefail

echo "🔧 ZFS Boot Fix Script (Installer Version)"
echo "========================================="
echo ""
echo "This script will help fix ZFS boot issues from the NixOS installer."
echo ""

# Check if we're running from the NixOS installer
if [[ ! -f /etc/NIXOS ]]; then
    echo "❌ This script should be run from the NixOS installer ISO"
    echo "Please boot from the NixOS installer and run this script again."
    exit 1
fi

# First, ensure we have the necessary tools
echo "📦 Loading ZFS kernel modules..."
modprobe zfs || {
    echo "❌ Failed to load ZFS kernel module"
    echo "Make sure you're using a NixOS installer with ZFS support"
    exit 1
}

echo "🔍 Checking for existing ZFS pools..."
if /run/current-system/sw/bin/zpool list 2>/dev/null | grep -q zroot; then
    echo "✅ Found zroot pool"
    /run/current-system/sw/bin/zpool status zroot
else
    echo "🔄 Importing zroot pool..."
    if /run/current-system/sw/bin/zpool import -f zroot; then
        echo "✅ Successfully imported zroot pool"
    else
        echo "❌ Failed to import zroot pool"
        echo "Available pools:"
        /run/current-system/sw/bin/zpool import
        exit 1
    fi
fi

echo ""
echo "🗂️ Checking ZFS datasets..."
/run/current-system/sw/bin/zfs list -t filesystem | grep zroot || true

echo ""
echo "🗂️ Current ZFS mountpoints:"
/run/current-system/sw/bin/zfs get -H -o name,value mountpoint | grep zroot || true

echo ""
echo "📁 Mounting filesystems for repair..."

# Ensure /mnt exists
mkdir -p /mnt

# Mount root filesystem
echo "Mounting zroot/root/nixos to /mnt..."
if mount -t zfs zroot/root/nixos /mnt; then
    echo "✅ Mounted zroot/root/nixos"
else
    echo "❌ Failed to mount zroot/root/nixos"
    exit 1
fi

# Mount other filesystems
mkdir -p /mnt/{home,nix,persist,boot}

echo "Mounting other ZFS datasets..."
mount -t zfs zroot/home /mnt/home || echo "⚠️ Failed to mount /home"
mount -t zfs zroot/nix /mnt/nix || echo "⚠️ Failed to mount /nix"  
mount -t zfs zroot/persist /mnt/persist || echo "⚠️ Failed to mount /persist"

# Mount boot partition
echo "Mounting boot partition..."
# Try to find the ESP partition
BOOT_DEV=$(lsblk -no NAME,FSTYPE | grep -E "vfat" | awk '{print "/dev/"$1}' | head -1)
if [[ -z "$BOOT_DEV" ]]; then
    # Try another method
    BOOT_DEV=$(fdisk -l 2>/dev/null | grep "EFI System" | awk '{print $1}' | head -1)
fi

if [[ -n "$BOOT_DEV" ]]; then
    mount "$BOOT_DEV" /mnt/boot && echo "✅ Mounted boot partition: $BOOT_DEV" || echo "⚠️ Failed to mount boot partition"
else
    echo "⚠️ Could not find boot partition automatically"
    echo "Available block devices:"
    lsblk
    echo ""
    echo "Please mount manually: mount /dev/YOUR_BOOT_DEVICE /mnt/boot"
fi

echo ""
echo "🔧 Ready to rebuild system..."
echo ""
echo "📝 Next steps:"
echo "1. If boot partition wasn't mounted, mount it manually"
echo "2. Change to the configuration directory:"
echo "   cd /mnt/home/amoon/refactor"
echo "3. Rebuild the system:"
echo "   nixos-install --flake .#nixos-dev --no-root-passwd"
echo "4. After rebuild completes:"
echo "   umount -R /mnt"
echo "   reboot"
echo ""
echo "The updated configuration includes fixes for the ZFS boot issue."