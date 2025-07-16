#!/usr/bin/env bash
# NixOS Btrfs Installation Script with Libre Kernel
set -euo pipefail

# Configuration
DISK="${1:-/dev/vda}"
HOSTNAME="${2:-nixos-btrfs}"
PLATFORM="${3:-qemu}"  # qemu, baremetal
FLAKE_URL="github:anthonymoon/nixos-zfsroot"

echo "🚀 NixOS Btrfs Installation Script"
echo "=================================="
echo ""
echo "This will install NixOS with Btrfs and Linux Libre kernel on $DISK"
echo "Platform: $PLATFORM"
echo "Hostname: $HOSTNAME"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root"
    exit 1
fi

# Check for existing filesystems
echo "🔍 Checking disk $DISK..."
if mount | grep -q "$DISK"; then
    echo "❌ Disk $DISK has mounted partitions!"
    echo "Please unmount all partitions first."
    exit 1
fi

echo "⚠️  WARNING: This will DESTROY ALL DATA on $DISK"
lsblk "$DISK" 2>/dev/null || true
echo ""
read -p "Type 'yes' to continue: " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Installation cancelled"
    exit 1
fi

echo "📦 Installing with disko and Btrfs..."

# Clone the repository
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

echo "Cloning configuration..."
git clone https://github.com/anthonymoon/nixos-zfsroot.git .

# Update disk device in disko config
sed -i "s|/dev/disk/by-id/PLACEHOLDER|$DISK|g" disko-config-btrfs.nix

# Determine the flake target
case "$PLATFORM" in
    qemu)
        FLAKE_TARGET="nixos-qemu-btrfs"
        ;;
    baremetal)
        FLAKE_TARGET="nixos-btrfs"
        ;;
    *)
        echo "❌ Unknown platform: $PLATFORM"
        exit 1
        ;;
esac

# Run disko to partition and create filesystems
echo "🔧 Partitioning disk and creating Btrfs filesystem..."
nix --experimental-features "nix-command flakes" run github:nix-community/disko -- \
    --mode disko \
    --flake ".#$FLAKE_TARGET"

# Mount check
echo "📁 Verifying mounts..."
mount | grep -E "(btrfs|vfat)" || {
    echo "❌ Filesystems not mounted properly"
    exit 1
}

# Show Btrfs structure
echo "📊 Btrfs subvolume layout:"
btrfs subvolume list /mnt

# Install NixOS
echo "🔧 Installing NixOS with Linux Libre kernel..."
nixos-install --flake ".#$FLAKE_TARGET" --no-root-passwd

# Create post-install script
cat > /mnt/root/post-install-btrfs.sh << 'EOF'
#!/usr/bin/env bash
echo "🎯 Btrfs Post-Installation Setup"
echo "================================"

# Set up Btrfs maintenance
echo "Setting up Btrfs scrub timer..."
systemctl enable btrfs-scrub@-.timer

# Enable snapshot service
echo "Enabling automatic snapshots..."
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer

# Create initial snapshots
echo "Creating initial snapshots..."
snapper -c home create --description "Initial installation"

# Show Btrfs filesystem info
echo ""
echo "📊 Btrfs filesystem information:"
btrfs filesystem show
echo ""
btrfs filesystem df /
echo ""
echo "📸 Snapshots:"
snapper -c home list

# Set user password
echo ""
echo "Please set password for user amoon:"
passwd amoon

echo ""
echo "✅ Post-installation complete!"
echo ""
echo "Optimizations applied:"
echo "- Btrfs with zstd compression"
echo "- Automatic snapshots configured"
echo "- Weekly scrub enabled"
echo "- Linux Libre kernel (no proprietary blobs)"
echo "- Optimized mount options for SSD"
echo ""
echo "You can now reboot into your new system."
EOF

chmod +x /mnt/root/post-install-btrfs.sh

# Create Btrfs maintenance script
cat > /mnt/root/btrfs-maintenance.sh << 'EOF'
#!/usr/bin/env bash
echo "🔧 Btrfs Maintenance Tasks"
echo "========================="

# Balance filesystem
echo "Running filesystem balance..."
btrfs balance start -dusage=5 -musage=5 /

# Show filesystem usage
echo ""
echo "Filesystem usage:"
btrfs filesystem df /
echo ""
btrfs device stats /

# Show compression ratio
echo ""
echo "Compression statistics:"
compsize /nix /home

# List snapshots
echo ""
echo "Current snapshots:"
snapper -c home list
EOF

chmod +x /mnt/root/btrfs-maintenance.sh

# Cleanup
cd /
rm -rf "$TEMP_DIR"

echo ""
echo "✅ Installation complete!"
echo ""
echo "📋 System Summary:"
echo "- Platform: $PLATFORM"
echo "- Hostname: $HOSTNAME"
echo "- Filesystem: Btrfs with compression"
echo "- Kernel: Linux Libre (latest)"
echo "- Subvolumes: @, @home, @nix, @persist, @log, @cache, @snapshots"
echo ""
echo "📝 Next steps:"
echo "1. Set root password: passwd"
echo "2. Reboot: reboot"
echo "3. After reboot, run: /root/post-install-btrfs.sh"
echo "4. For maintenance, use: /root/btrfs-maintenance.sh"
echo ""
echo "🌟 Enjoy your libre NixOS system with Btrfs!"