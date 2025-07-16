#!/usr/bin/env bash
set -euo pipefail

echo "NixOS Installer"
echo "==============="
echo ""
echo "This will install NixOS with configuration from:"
echo "https://github.com/anthonymoon/nixos-btrfs"
echo ""
echo "WARNING: This will ERASE the target disk!"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)"
   exit 1
fi

# Default values
DISK="${1:-/dev/sda}"
FLAKE_URL="github:anthonymoon/nixos-btrfs#nixos"

# Show disk info
echo "Target disk: $DISK"
echo ""
if [[ -b "$DISK" ]]; then
    echo "Disk information:"
    lsblk "$DISK" || true
    echo ""
else
    echo "ERROR: $DISK is not a block device"
    exit 1
fi

# Confirmation
read -p "Continue with installation to $DISK? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Installation cancelled"
    exit 0
fi

echo ""
echo "Starting installation..."
echo ""

# Partition and format disk
echo "==> Partitioning disk with disko..."
nix run github:nix-community/disko -- --mode disko --flake "$FLAKE_URL"

# Install NixOS
echo ""
echo "==> Installing NixOS..."
nixos-install --flake "$FLAKE_URL" --no-root-password --no-write-lock-file

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "1. Reboot into your new system"
echo "2. Set user password: passwd amoon"
echo "3. Deploy updates: sudo nixos-rebuild switch --flake github:anthonymoon/nixos-btrfs#nixos"
echo ""
echo "Enjoy your new NixOS system!"