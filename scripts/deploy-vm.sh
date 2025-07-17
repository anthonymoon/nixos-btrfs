#!/usr/bin/env bash
set -euo pipefail

# Automagic VM deployment - formats disk and installs in one go

usage() {
  echo "Usage: $0 [DISK] [HOST] [OPTIONS]"
  echo ""
  echo "Arguments:"
  echo "  DISK    Target disk (default: /dev/sda)"
  echo "  HOST    Host configuration (default: vm, options: vm, vm-zfs)"
  echo ""
  echo "Options:"
  echo "  -y, --auto-accept    Auto-accept disk wipe confirmation"
  echo "  -r, --auto-reboot    Auto-reboot after installation"
  echo "  -a, --auto           Enable both auto-accept and auto-reboot"
  echo "  -h, --help           Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0                                    # Interactive install to /dev/sda"
  echo "  $0 /dev/vda vm-zfs                   # Install ZFS to /dev/vda"
  echo "  $0 /dev/sda vm --auto-accept         # Skip confirmation"
  echo "  $0 /dev/sda vm --auto-reboot         # Auto-reboot after install"
  echo "  $0 /dev/sda vm --auto                # Fully automated"
  echo ""
}

# Initialize variables
DISK="/dev/sda"
HOST="vm"
AUTO_ACCEPT=""
AUTO_REBOOT=""

# Parse named flags
while [[ $# -gt 0 ]]; do
  case $1 in
    --help|-h)
      usage
      exit 0
      ;;
    --auto-accept|-y)
      AUTO_ACCEPT="true"
      shift
      ;;
    --auto-reboot|-r)
      AUTO_REBOOT="true"
      shift
      ;;
    --auto|-a)
      AUTO_ACCEPT="true"
      AUTO_REBOOT="true"
      shift
      ;;
    -*)
      echo "Unknown option $1"
      echo "Use --help for usage information"
      exit 1
      ;;
    *)
      if [[ -z "${DISK_SET:-}" ]]; then
        DISK="$1"
        DISK_SET="true"
      elif [[ -z "${HOST_SET:-}" ]]; then
        HOST="$1"
        HOST_SET="true"
      fi
      shift
      ;;
  esac
done

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                 Automagic NixOS VM Deployer                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Target: $HOST on $DISK"
if [[ "$HOST" == *"zfs"* ]]; then
  echo "Filesystem: ZFS"
else
  echo "Filesystem: BTRFS"
fi
if [[ "$AUTO_ACCEPT" == "true" ]]; then
  echo "Mode: Auto-accept enabled"
fi
if [[ "$AUTO_REBOOT" == "true" ]]; then
  echo "Mode: Auto-reboot enabled"
fi
echo ""

# Warning and confirmation
if [[ "$AUTO_ACCEPT" != "true" ]]; then
  echo "WARNING: This will COMPLETELY ERASE $DISK"
  read -p "Continue? (yes/NO): " confirm
  [[ "$confirm" != "yes" ]] && exit 0
else
  echo "WARNING: This will COMPLETELY ERASE $DISK"
  echo "Auto-accept enabled - proceeding automatically..."
  sleep 2
fi

echo "→ Wiping disk..."
dd if=/dev/zero of="$DISK" bs=1M count=100 status=progress 2>/dev/null || true
sync

echo "→ Creating partitions..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 1GiB
parted -s "$DISK" set 1 esp on

# Check if we're using ZFS
if [[ "$HOST" == *"zfs"* ]]; then
  echo "→ Setting up for ZFS..."
  parted -s "$DISK" mkpart primary 1GiB 100%
else
  parted -s "$DISK" mkpart primary btrfs 1GiB 100%
fi

sleep 2
partprobe "$DISK"

echo "→ Formatting..."
mkfs.fat -F32 -n BOOT "${DISK}1" >/dev/null 2>&1

if [[ "$HOST" == *"zfs"* ]]; then
  echo "→ Creating ZFS pool..."
  zpool create -f \
    -o ashift=12 \
    -o autotrim=on \
    -O compression=lz4 \
    -O acltype=posixacl \
    -O xattr=sa \
    -O relatime=on \
    -O normalization=formD \
    -O mountpoint=none \
    rpool "${DISK}2"
  
  echo "→ Creating ZFS datasets..."
  zfs create -o mountpoint=legacy rpool/root
  zfs create -o mountpoint=legacy rpool/home
  zfs create -o mountpoint=legacy -o compression=zstd rpool/nix
  zfs create -o mountpoint=legacy -o compression=off rpool/tmp
  zfs create -o mountpoint=legacy rpool/var
  
  echo "→ Mounting ZFS filesystems..."
  mount -t zfs rpool/root /mnt
  mkdir -p /mnt/{boot,home,nix,tmp,var}
  mount "${DISK}1" /mnt/boot
  mount -t zfs rpool/home /mnt/home
  mount -t zfs rpool/nix /mnt/nix
  mount -t zfs rpool/tmp /mnt/tmp
  mount -t zfs rpool/var /mnt/var
else
  echo "→ Creating BTRFS filesystem..."
  mkfs.btrfs -f -L nixos "${DISK}2" >/dev/null 2>&1
  
  echo "→ Creating BTRFS layout..."
  mount "${DISK}2" /mnt
  btrfs subvolume create /mnt/@ >/dev/null
  btrfs subvolume create /mnt/@home >/dev/null
  btrfs subvolume create /mnt/@nix >/dev/null
  btrfs subvolume create /mnt/@tmp >/dev/null
  btrfs subvolume create /mnt/@var >/dev/null
  umount /mnt
  
  echo "→ Mounting BTRFS filesystems..."
  mount -o compress=zstd:3,noatime,subvol=@ "${DISK}2" /mnt
  mkdir -p /mnt/{boot,home,nix,tmp,var}
  mount "${DISK}1" /mnt/boot
  mount -o compress=zstd:3,noatime,subvol=@home "${DISK}2" /mnt/home
  mount -o compress=zstd:6,noatime,subvol=@nix "${DISK}2" /mnt/nix
  mount -o compress=zstd:1,noatime,subvol=@tmp "${DISK}2" /mnt/tmp
  mount -o compress=zstd:3,noatime,subvol=@var "${DISK}2" /mnt/var
fi

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

if [[ "$AUTO_REBOOT" == "true" ]]; then
  echo "Auto-reboot enabled - rebooting in 5 seconds..."
  echo "After reboot:"
  echo "  1. Login as 'amoon' with password 'nixos'"
  echo "  2. passwd (to change password)"
  echo ""
  sleep 5
  reboot
else
  echo "Next steps:"
  echo "  1. reboot"
  echo "  2. Login as 'amoon' with password 'nixos'"
  echo "  3. passwd (to change password)"
fi