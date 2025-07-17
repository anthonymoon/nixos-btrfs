#!/usr/bin/env bash
# Mount existing NixOS system for repair/maintenance
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

# Banner
echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                  NixOS System Mount Tool                    ║"
echo "║            Mount existing system for maintenance            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Function to detect filesystem type
detect_filesystem() {
    local device="$1"
    
    if blkid "$device" | grep -q "TYPE=\"btrfs\""; then
        echo "btrfs"
    elif blkid "$device" | grep -q "TYPE=\"zfs_member\""; then
        echo "zfs"
    elif blkid "$device" | grep -q "TYPE=\"ext4\""; then
        echo "ext4"
    elif blkid "$device" | grep -q "TYPE=\"crypto_LUKS\""; then
        echo "luks"
    else
        echo "unknown"
    fi
}

# Function to detect if device is encrypted
is_encrypted() {
    local device="$1"
    blkid "$device" | grep -q "TYPE=\"crypto_LUKS\""
}

# Function to find root partition
find_root_partition() {
    local disk="$1"
    
    # Try different common patterns
    for part in "${disk}p2" "${disk}2" "${disk}-part2"; do
        if [[ -b "$part" ]]; then
            echo "$part"
            return 0
        fi
    done
    
    # Fallback: scan all partitions
    for part in $(lsblk -lpno NAME "$disk" | grep -v "^$disk$"); do
        if [[ -b "$part" ]]; then
            local fs_type=$(detect_filesystem "$part")
            if [[ "$fs_type" == "btrfs" ]] || [[ "$fs_type" == "ext4" ]] || [[ "$fs_type" == "luks" ]]; then
                echo "$part"
                return 0
            fi
        fi
    done
    
    return 1
}

# Function to mount BTRFS subvolumes
mount_btrfs_subvolumes() {
    local device="$1"
    local mount_point="$2"
    
    log_info "Mounting BTRFS subvolumes from $device"
    
    # Get common mount options for BTRFS
    local mount_opts="compress=zstd:3,noatime,ssd,space_cache=v2"
    
    # Mount root subvolume
    mount -t btrfs -o "subvol=@,$mount_opts" "$device" "$mount_point"
    
    # Create and mount other subvolumes
    local subvols=("home" "nix" "var" "tmp" ".snapshots")
    for subvol in "${subvols[@]}"; do
        local subvol_path="$mount_point/$subvol"
        local subvol_name="@$subvol"
        [[ "$subvol" == ".snapshots" ]] && subvol_name="@snapshots"
        
        mkdir -p "$subvol_path"
        if btrfs subvolume list "$mount_point" | grep -q "$subvol_name"; then
            mount -t btrfs -o "subvol=$subvol_name,$mount_opts" "$device" "$subvol_path"
            log_info "Mounted $subvol_name to $subvol_path"
        else
            log_warn "Subvolume $subvol_name not found, skipping"
        fi
    done
}

# Function to import and mount ZFS pools
mount_zfs_pools() {
    log_info "Detecting and importing ZFS pools"
    
    # Load ZFS module
    modprobe zfs || {
        log_error "Failed to load ZFS module"
        return 1
    }
    
    # Import all available pools
    zpool import -a -f 2>/dev/null || log_warn "Some ZFS pools may not have been imported"
    
    # List available pools
    local pools=$(zpool list -H -o name 2>/dev/null)
    if [[ -z "$pools" ]]; then
        log_error "No ZFS pools found"
        return 1
    fi
    
    log_info "Found ZFS pools: $pools"
    
    # Mount ZFS filesystems
    zfs mount -a
    
    # Check if root is mounted
    if mountpoint -q /mnt; then
        log_info "ZFS root filesystem mounted"
        return 0
    else
        # Try to mount root manually
        for pool in $pools; do
            if zfs list "$pool/root" >/dev/null 2>&1; then
                zfs set mountpoint=/mnt "$pool/root"
                zfs mount "$pool/root"
                log_info "Mounted ZFS root from $pool/root"
                return 0
            fi
        done
        
        log_error "Could not mount ZFS root filesystem"
        return 1
    fi
}

# Function to mount boot partition
mount_boot_partition() {
    local disk="$1"
    
    log_info "Mounting boot partition"
    
    # Find EFI System Partition
    for part in "${disk}p1" "${disk}1" "${disk}-part1"; do
        if [[ -b "$part" ]] && blkid "$part" | grep -q "TYPE=\"vfat\""; then
            mkdir -p /mnt/boot
            mount "$part" /mnt/boot
            log_info "Mounted boot partition: $part"
            return 0
        fi
    done
    
    log_warn "Boot partition not found or already mounted"
    return 1
}

# Function to bind mount system directories
bind_mount_system() {
    log_info "Bind mounting system directories"
    
    local dirs=("/dev" "/proc" "/sys" "/run")
    for dir in "${dirs[@]}"; do
        if [[ -d "/mnt$dir" ]]; then
            mount --bind "$dir" "/mnt$dir"
            log_info "Bind mounted $dir"
        else
            mkdir -p "/mnt$dir"
            mount --bind "$dir" "/mnt$dir"
            log_info "Created and bind mounted $dir"
        fi
    done
    
    # Mount devpts and tmpfs
    mount -t devpts devpts /mnt/dev/pts || log_warn "Failed to mount devpts"
    mount -t tmpfs tmpfs /mnt/tmp || log_warn "Failed to mount tmpfs on /tmp"
}

# Main script logic
main() {
    # Detect available disks
    log_step "Detecting available disks"
    local disks=$(lsblk -dpno NAME | grep -E '/dev/(sd|nvme|vd)' | head -10)
    
    if [[ -z "$disks" ]]; then
        log_error "No suitable disks found"
        exit 1
    fi
    
    echo "Available disks:"
    echo "$disks" | while read disk; do
        local size=$(lsblk -dpno SIZE "$disk")
        local model=$(lsblk -dpno MODEL "$disk" | head -1)
        echo "  $disk ($size) - $model"
    done
    
    # Select disk
    echo ""
    read -p "Enter disk to mount (e.g., /dev/sda): " selected_disk
    
    if [[ ! -b "$selected_disk" ]]; then
        log_error "Invalid disk: $selected_disk"
        exit 1
    fi
    
    # Find root partition
    log_step "Finding root partition"
    local root_partition=$(find_root_partition "$selected_disk")
    
    if [[ -z "$root_partition" ]]; then
        log_error "Could not find root partition on $selected_disk"
        exit 1
    fi
    
    log_info "Found root partition: $root_partition"
    
    # Handle encryption
    local actual_device="$root_partition"
    if is_encrypted "$root_partition"; then
        log_step "Unlocking encrypted partition"
        echo "Partition is encrypted with LUKS"
        
        local mapper_name="nixos-root"
        read -s -p "Enter LUKS password: " luks_password
        echo ""
        
        echo "$luks_password" | cryptsetup open "$root_partition" "$mapper_name"
        actual_device="/dev/mapper/$mapper_name"
        log_info "Unlocked encrypted partition: $actual_device"
    fi
    
    # Detect filesystem type
    local fs_type=$(detect_filesystem "$actual_device")
    log_info "Detected filesystem: $fs_type"
    
    # Create mount point
    mkdir -p /mnt
    
    # Mount based on filesystem type
    log_step "Mounting filesystem"
    
    case "$fs_type" in
        "btrfs")
            mount_btrfs_subvolumes "$actual_device" "/mnt"
            ;;
        "zfs_member"|"zfs")
            mount_zfs_pools
            ;;
        "ext4")
            mount "$actual_device" /mnt
            log_info "Mounted ext4 root filesystem"
            ;;
        *)
            log_error "Unsupported filesystem type: $fs_type"
            exit 1
            ;;
    esac
    
    # Mount boot partition
    mount_boot_partition "$selected_disk"
    
    # Bind mount system directories
    bind_mount_system
    
    # Show mount status
    log_step "Mount summary"
    echo "Mounted filesystems:"
    mount | grep "/mnt" | while read line; do
        echo "  $line"
    done
    
    echo ""
    log_info "System successfully mounted at /mnt"
    echo ""
    echo "You can now:"
    echo "  - chroot /mnt"
    echo "  - nixos-rebuild switch --flake /mnt/etc/nixos#hostname"
    echo "  - Edit configuration files in /mnt/etc/nixos"
    echo ""
    echo "To unmount when finished:"
    echo "  umount -R /mnt"
    if is_encrypted "$root_partition"; then
        echo "  cryptsetup close nixos-root"
    fi
    if [[ "$fs_type" == "zfs" ]]; then
        echo "  zpool export -a"
    fi
}

# Cleanup function
cleanup() {
    log_info "Cleaning up mounts..."
    umount -R /mnt 2>/dev/null || true
    
    if [[ -e "/dev/mapper/nixos-root" ]]; then
        cryptsetup close nixos-root 2>/dev/null || true
    fi
    
    if command -v zpool >/dev/null 2>&1; then
        zpool export -a 2>/dev/null || true
    fi
}

# Set up cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"