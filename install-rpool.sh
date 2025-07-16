#!/usr/bin/env bash
# NixOS QEMU VM Installation with rpool
set -euo pipefail

# Configuration
DISK="${1:-/dev/vda}"
HOSTNAME="nixos-dev1"
FLAKE_URL="github:anthonymoon/nixos-zfsroot"

echo "🚀 NixOS QEMU Installation Script"
echo "================================="
echo ""
echo "This will install NixOS with ZFS (rpool) on $DISK"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root"
    exit 1
fi

echo "🔄 Checking for existing ZFS pools..."
if zpool list 2>/dev/null | grep -E "rpool"; then
    echo "❌ Existing rpool found!"
    echo "Please destroy it first with: zpool destroy -f rpool"
    exit 1
fi

echo "⚠️  WARNING: This will DESTROY ALL DATA on $DISK"
echo ""
read -p "Type 'yes' to continue: " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Installation cancelled"
    exit 1
fi

echo "📦 Installing with disko..."

# Clone the repository
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

echo "Cloning configuration..."
git clone https://github.com/anthonymoon/nixos-zfsroot.git .

# Update disk device in disko config
sed -i "s|/dev/disk/by-id/PLACEHOLDER|$DISK|g" disko-config-rpool.nix

# Run disko to partition and create filesystems
echo "Running disko..."
nix --experimental-features "nix-command flakes" run github:nix-community/disko -- \
    --mode disko \
    --flake ".#nixos-dev1"

# Install NixOS
echo "Installing NixOS..."
nixos-install --flake ".#nixos-dev1" --no-root-passwd

# Cleanup
cd /
rm -rf "$TEMP_DIR"

echo ""
echo "✅ Installation complete!"
echo ""
echo "Next steps:"
echo "1. Set root password: passwd"
echo "2. Reboot: reboot"
echo "3. After reboot, set user password: passwd amoon"
echo ""
echo "Enjoy your NixOS QEMU system with ZFS!"