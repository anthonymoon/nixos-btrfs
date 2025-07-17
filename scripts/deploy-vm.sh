#!/usr/bin/env bash
set -euo pipefail

# Automagic VM deployment - formats disk and installs in one go

DISK="${1:-/dev/sda}"
HOST="${2:-vm}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                 Automagic NixOS VM Deployer                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Target: $HOST on $DISK"
echo ""

# Warning
echo "WARNING: This will COMPLETELY ERASE $DISK"
read -p "Continue? (yes/NO): " confirm
[[ "$confirm" != "yes" ]] && exit 0

echo "→ Wiping disk..."
dd if=/dev/zero of="$DISK" bs=1M count=100 status=progress 2>/dev/null || true
sync

echo "→ Creating partitions..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 1GiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary btrfs 1GiB 100%
sleep 2
partprobe "$DISK"

echo "→ Formatting..."
mkfs.fat -F32 -n BOOT "${DISK}1" >/dev/null 2>&1
mkfs.btrfs -f -L nixos "${DISK}2" >/dev/null 2>&1

echo "→ Creating BTRFS layout..."
mount "${DISK}2" /mnt
btrfs subvolume create /mnt/@ >/dev/null
btrfs subvolume create /mnt/@home >/dev/null
btrfs subvolume create /mnt/@nix >/dev/null
btrfs subvolume create /mnt/@tmp >/dev/null
btrfs subvolume create /mnt/@var >/dev/null
umount /mnt

echo "→ Mounting filesystems..."
mount -o compress=zstd:3,noatime,subvol=@ "${DISK}2" /mnt
mkdir -p /mnt/{boot,home,nix,tmp,var}
mount "${DISK}1" /mnt/boot
mount -o compress=zstd:3,noatime,subvol=@home "${DISK}2" /mnt/home
mount -o compress=zstd:6,noatime,subvol=@nix "${DISK}2" /mnt/nix
mount -o compress=zstd:1,noatime,subvol=@tmp "${DISK}2" /mnt/tmp
mount -o compress=zstd:3,noatime,subvol=@var "${DISK}2" /mnt/var

echo "→ Generating config..."
nixos-generate-config --root /mnt >/dev/null 2>&1

echo "→ Installing NixOS (this will take a few minutes)..."
NIX_ARGS=""
if [[ "$HOST" == *"zfs"* ]]; then
  export NIXPKGS_ALLOW_BROKEN=1
  NIX_ARGS="--impure"
fi

nixos-install \
  --root /mnt \
  --no-root-password \
  --flake "github:anthonymoon/nixos-btrfs#$HOST" \
  --max-jobs 2 \
  --option narinfo-cache-negative-ttl 0 \
  $NIX_ARGS \
  2>&1 | grep -E "copying|building|installing" || true

echo ""
echo "✓ Installation complete!"
echo ""
echo "Next steps:"
echo "  1. reboot"
echo "  2. Login as 'amoon' with password 'nixos'"
echo "  3. passwd (to change password)"