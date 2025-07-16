#!/usr/bin/env bash
set -euo pipefail

echo "🔧 ZFS Boot Fix Script"
echo "======================"
echo ""
echo "This script will help fix ZFS boot issues."
echo ""

# Check if we're running from the NixOS installer
if [[ ! -f /etc/NIXOS ]]; then
    echo "❌ This script should be run from the NixOS installer ISO"
    echo "Please boot from the NixOS installer and run this script again."
    exit 1
fi

echo "🔍 Checking for existing ZFS pools..."
if zpool list 2>/dev/null | grep -q zroot; then
    echo "✅ Found zroot pool"
    zpool status zroot
else
    echo "🔄 Importing zroot pool..."
    if zpool import -f zroot; then
        echo "✅ Successfully imported zroot pool"
    else
        echo "❌ Failed to import zroot pool"
        echo "Available pools:"
        zpool import
        exit 1
    fi
fi

echo ""
echo "🗂️ Checking ZFS datasets..."
zfs list -t filesystem | grep zroot || true

echo ""
echo "🗂️ Current ZFS mountpoints:"
zfs get -H -o name,value mountpoint | grep zroot || true

echo ""
echo "📁 Mounting filesystems for repair..."

# Ensure /mnt exists
mkdir -p /mnt

# Mount root filesystem
echo "Mounting zroot/root to /mnt..."
if mount -t zfs zroot/root /mnt; then
    echo "✅ Mounted zroot/root"
else
    echo "❌ Failed to mount zroot/root"
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
BOOT_DEV=$(lsblk -no NAME,LABEL | grep -E "(ESP|EFI)" | awk '{print "/dev/"$1}' | head -1)
if [[ -n "$BOOT_DEV" ]]; then
    mount "$BOOT_DEV" /mnt/boot || echo "⚠️ Failed to mount boot partition"
    echo "✅ Mounted boot partition: $BOOT_DEV"
else
    echo "⚠️ Could not find boot partition"
fi

echo ""
echo "🔧 Rebuilding system with fixed configuration..."

# Check if we have the fixed flake
if [[ -f /mnt/home/amoon/refactor/flake.nix ]]; then
    echo "✅ Found flake configuration"
    cd /mnt/home/amoon/refactor
    
    echo "Rebuilding system with fixed ZFS configuration..."
    nixos-install --flake .#nixos-dev --no-root-passwd
    
    echo ""
    echo "✅ System rebuilt successfully!"
    echo ""
    echo "🎯 Next steps:"
    echo "1. Unmount filesystems: umount -R /mnt"
    echo "2. Reboot the system: reboot"
    echo "3. The system should now boot properly with ZFS root"
    
else
    echo "❌ Could not find flake configuration"
    echo "Please ensure the fixed flake.nix is available"
    exit 1
fi