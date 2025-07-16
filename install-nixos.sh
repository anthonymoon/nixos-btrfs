#!/usr/bin/env bash
# Automated NixOS ZFS Installation Script
# Supports: bare metal, QEMU, HyperV

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
FLAKE_URL="${FLAKE_URL:-github:yourusername/nixos-config}"
HOSTNAME="nixos-dev"
USERNAME="amoon"
MIN_RAM_GB=4
MIN_DISK_GB=20
ZFS_ARC_MIN_GB=2
ZFS_ARC_MAX_GB=8

# Functions
print_banner() {
    echo -e "${BLUE}"
    cat << "EOF"
     _   _ _       ___  ____   ______ _____ ____  
    | \ | (_)     / _ \/ ___| |___  /|  ___/ ___| 
    |  \| |___  _| | | \___ \    / / | |_  \___ \ 
    | |\  | \ \/ / |_| |___) |  / /  |  _|  ___) |
    |_| \_|_|>  < \___/|____/  /_/   |_|   |____/ 
            /_/\_\                                 
    
    Multi-Platform ZFS Installation Script
EOF
    echo -e "${NC}"
}

log() {
    echo -e "${BLUE}==>${NC} $1"
}

error() {
    echo -e "${RED}Error:${NC} $1" >&2
    exit 1
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

# Cleanup function for error handling
cleanup() {
    log "Cleaning up on exit..."
    umount -R /mnt 2>/dev/null || true
    zpool export zroot 2>/dev/null || true
    swapoff -a 2>/dev/null || true
}

# Set up error handling
trap cleanup EXIT ERR

# Validate configuration
validate_config() {
    log "Validating configuration..."
    
    # Check FLAKE_URL format
    if [[ ! "$FLAKE_URL" =~ ^(github:|git\+|https:|file:) ]]; then
        error "Invalid FLAKE_URL format: $FLAKE_URL"
    fi
    
    # Check hostname format
    if [[ ! "$HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9]$ ]]; then
        error "Invalid hostname format: $HOSTNAME"
    fi
    
    # Check username format
    if [[ ! "$USERNAME" =~ ^[a-z][a-z0-9_-]*$ ]]; then
        error "Invalid username format: $USERNAME"
    fi
    
    success "Configuration validated"
}

# Detect virtualization
detect_platform() {
    log "Detecting platform..."
    
    if systemd-detect-virt --quiet; then
        local virt=$(systemd-detect-virt)
        case $virt in
            kvm|qemu)
                echo "qemu"
                success "Detected QEMU/KVM virtualization"
                ;;
            microsoft)
                echo "hyperv"
                success "Detected HyperV virtualization"
                ;;
            *)
                echo "vm-other"
                warning "Detected unknown virtualization: $virt"
                ;;
        esac
    else
        echo "baremetal"
        success "Detected bare metal installation"
    fi
}

# Detect disk
detect_disk() {
    log "Detecting disk..."
    
    for disk in /dev/sda /dev/vda /dev/nvme0n1; do
        if [[ -b "$disk" ]]; then
            echo "$disk"
            success "Found disk: $disk"
            return 0
        fi
    done
    
    error "No suitable disk found!"
}

# Get partition names
get_partitions() {
    local disk=$1
    if [[ "$disk" =~ nvme ]]; then
        echo "${disk}p1 ${disk}p2"
    else
        echo "${disk}1 ${disk}2"
    fi
}

# Check system requirements
check_system_requirements() {
    log "Checking system requirements..."
    
    # Check RAM
    local ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local ram_gb=$((ram_kb / 1024 / 1024))
    
    if [[ $ram_gb -lt $MIN_RAM_GB ]]; then
        error "Insufficient RAM: ${ram_gb}GB (minimum: ${MIN_RAM_GB}GB)"
    fi
    
    # Adjust ZFS ARC based on available RAM
    if [[ $ram_gb -ge 16 ]]; then
        ZFS_ARC_MAX_GB=$((ram_gb / 2))
    elif [[ $ram_gb -ge 8 ]]; then
        ZFS_ARC_MAX_GB=$((ram_gb / 3))
    fi
    
    success "RAM: ${ram_gb}GB (ZFS ARC max: ${ZFS_ARC_MAX_GB}GB)"
}

# Check disk space
check_disk_space() {
    local disk=$1
    log "Checking disk space for $disk..."
    
    # Get disk size in GB
    local disk_bytes=$(lsblk -b -n -o SIZE "$disk" | head -1)
    local disk_gb=$((disk_bytes / 1024 / 1024 / 1024))
    
    if [[ $disk_gb -lt $MIN_DISK_GB ]]; then
        error "Insufficient disk space: ${disk_gb}GB (minimum: ${MIN_DISK_GB}GB)"
    fi
    
    success "Disk space: ${disk_gb}GB"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
    
    # Check required tools
    local tools=("parted" "mkfs.vfat" "zpool" "zfs" "git" "sgdisk" "lsblk")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error "Required tool '$tool' not found"
        fi
    done
    
    # Check internet connection
    if ! ping -c 1 github.com &> /dev/null; then
        warning "No internet connection detected"
    fi
    
    success "All prerequisites met"
}

# Partition disk
partition_disk() {
    local disk=$1
    log "Partitioning $disk..."
    
    # Wipe disk
    wipefs -af "$disk"
    sgdisk -Z "$disk"
    
    # Create GPT table
    parted -s "$disk" mklabel gpt
    
    # Create ESP partition (1GB)
    parted -s "$disk" mkpart ESP fat32 1MB 1GB
    parted -s "$disk" set 1 esp on
    
    # Create ZFS partition (remaining)
    parted -s "$disk" mkpart primary 1GB 100%
    
    # Reload partition table
    partprobe "$disk"
    sleep 2
    
    success "Disk partitioned"
}

# Create ZFS pool
create_zfs_pool() {
    local disk=$1
    local zfs_part=$2
    
    log "Creating ZFS pool on $zfs_part..."
    
    # Create pool with optimal settings
    zpool create -f \
        -o ashift=12 \
        -o autotrim=on \
        -O compression=lz4 \
        -O acltype=posixacl \
        -O xattr=sa \
        -O relatime=on \
        -O normalization=formD \
        -O mountpoint=none \
        zroot "$zfs_part"
    
    # Set ZFS ARC limits
    log "Configuring ZFS ARC memory limits..."
    echo $((ZFS_ARC_MIN_GB * 1024 * 1024 * 1024)) > /sys/module/zfs/parameters/zfs_arc_min
    echo $((ZFS_ARC_MAX_GB * 1024 * 1024 * 1024)) > /sys/module/zfs/parameters/zfs_arc_max
    
    # Create datasets
    log "Creating ZFS datasets..."
    
    # Root - fast compression
    zfs create -o mountpoint=legacy -o compression=lz4 zroot/root
    
    # Home - balanced compression
    zfs create -o mountpoint=legacy -o compression=zstd-3 -o recordsize=1M zroot/home
    
    # Nix - maximum compression + deduplication
    zfs create -o mountpoint=legacy -o compression=zstd-6 -o recordsize=64k \
        -o dedup=on -o atime=off zroot/nix
    
    # Persist - system state
    zfs create -o mountpoint=legacy -o compression=lz4 zroot/persist
    
    # Reserved space
    zfs create -o refreservation=10G -o mountpoint=none zroot/reserved
    
    # Verify pool health
    if ! zpool status zroot | grep -q "state: ONLINE"; then
        error "ZFS pool creation failed or pool is not healthy"
    fi
    
    success "ZFS pool created with deduplication enabled on /nix"
    success "ZFS ARC configured: ${ZFS_ARC_MIN_GB}GB - ${ZFS_ARC_MAX_GB}GB"
}

# Mount filesystems
mount_filesystems() {
    local boot_part=$1
    
    log "Mounting filesystems..."
    
    # Mount root
    mount -t zfs zroot/root /mnt
    
    # Create mount points
    mkdir -p /mnt/{boot,home,nix,persist,etc/nixos}
    
    # Mount partitions
    mount "$boot_part" /mnt/boot
    mount -t zfs zroot/home /mnt/home
    mount -t zfs zroot/nix /mnt/nix
    mount -t zfs zroot/persist /mnt/persist
    
    success "Filesystems mounted"
}

# Generate configuration
generate_config() {
    local platform=$1
    
    log "Generating NixOS configuration..."
    
    # Generate hardware configuration
    nixos-generate-config --root /mnt
    
    # Get host ID
    local host_id=$(head -c 8 /etc/machine-id)
    
    # Create flake.nix
    cat > /mnt/etc/nixos/flake.nix << EOF
{
  description = "NixOS configuration for $HOSTNAME";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    nixos-config.url = "$FLAKE_URL";
  };

  outputs = { self, nixpkgs, nixos-config }: {
    nixosConfigurations.$HOSTNAME = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hardware-configuration.nix
        nixos-config.nixosConfigurations.nixos-dev.config
        {
          networking.hostId = "$host_id";
          
          # Platform-specific configuration
          ${generate_platform_config "$platform"}
        }
      ];
    };
  };
}
EOF
    
    success "Configuration generated"
}

# Generate platform-specific config
generate_platform_config() {
    local platform=$1
    
    case $platform in
        qemu)
            cat << 'EOF'
          # QEMU/KVM optimizations
          services.qemuGuest.enable = true;
          services.spice-vdagentd.enable = true;
          boot.kernelModules = [ "virtio_balloon" "virtio_console" "virtio_rng" ];
EOF
            ;;
        hyperv)
            cat << 'EOF'
          # HyperV optimizations
          virtualisation.hypervGuest = {
            enable = true;
            videoMode = "1920x1080";
          };
          boot.kernelParams = [ "video=hyperv_fb:1920x1080" ];
EOF
            ;;
        *)
            echo "# Bare metal - no specific virtualization config"
            ;;
    esac
}

# Install system
install_system() {
    log "Installing NixOS..."
    
    # Set up channels (for compatibility)
    nix-channel --add https://nixos.org/channels/nixos-24.05 nixos
    nix-channel --update
    
    # Validate flake before installation
    log "Validating flake configuration..."
    if ! nix flake check "/mnt/etc/nixos" 2>/dev/null; then
        warning "Flake validation failed, but continuing with installation"
    fi
    
    # Install with error handling
    if ! nixos-install --no-root-passwd --flake "/mnt/etc/nixos#$HOSTNAME"; then
        error "NixOS installation failed! Check logs for details."
    fi
    
    # Verify installation
    if [[ ! -f "/mnt/etc/nixos/configuration.nix" ]] && [[ ! -f "/mnt/etc/nixos/flake.nix" ]]; then
        error "Installation verification failed - no configuration found"
    fi
    
    success "NixOS installed successfully!"
}

# Post-install setup
post_install() {
    log "Running post-install setup..."
    
    # Create post-install script
    cat > /mnt/root/post-install.sh << 'EOF'
#!/usr/bin/env bash
set -e

echo "Running post-installation setup..."

# Set user password
echo "Please set password for user amoon:"
passwd amoon

# Update flake inputs
cd /etc/nixos
nix flake update

# Rebuild with latest
nixos-rebuild switch --flake .#nixos-dev

# Enable ZFS monitoring
systemctl enable zfs-zed.service
systemctl start zfs-zed.service

# Show ZFS status
echo ""
echo "ZFS Pool Status:"
zpool status -v
echo ""
echo "ZFS Deduplication Status:"
zpool list -o name,size,allocated,free,dedup,health
echo ""
echo "Dataset Usage:"
zfs list -o name,used,avail,refer,compressratio,dedup

echo ""
echo "Post-installation complete!"
echo "You can now reboot into your new system."
EOF
    
    chmod +x /mnt/root/post-install.sh
    
    warning "Run /root/post-install.sh after rebooting"
}

# Create backup configuration
create_backup() {
    local disk=$1
    log "Creating installation backup metadata..."
    
    cat > /tmp/nixos-install-backup.json << EOF
{
  "timestamp": "$(date -Iseconds)",
  "disk": "$disk",
  "platform": "$PLATFORM",
  "hostname": "$HOSTNAME",
  "username": "$USERNAME",
  "flake_url": "$FLAKE_URL",
  "zfs_arc_min": "${ZFS_ARC_MIN_GB}GB",
  "zfs_arc_max": "${ZFS_ARC_MAX_GB}GB"
}
EOF
    
    cp /tmp/nixos-install-backup.json /mnt/root/install-backup.json
    success "Backup metadata created"
}

# Main installation flow
main() {
    print_banner
    
    # Validate configuration first
    validate_config
    
    # Check prerequisites
    check_prerequisites
    
    # Check system requirements
    check_system_requirements
    
    # Detect platform
    PLATFORM=$(detect_platform)
    
    # Detect disk
    DISK=$(detect_disk)
    
    # Check disk space
    check_disk_space "$DISK"
    
    # Get partition names
    read -r BOOT_PART ZFS_PART <<< $(get_partitions "$DISK")
    
    # Show system information
    echo ""
    log "Installation Summary:"
    echo "  Platform: $PLATFORM"
    echo "  Disk: $DISK ($(lsblk -d -n -o SIZE "$DISK" | tr -d ' '))"
    echo "  Hostname: $HOSTNAME"
    echo "  Username: $USERNAME"
    echo "  Flake URL: $FLAKE_URL"
    echo "  ZFS ARC: ${ZFS_ARC_MIN_GB}GB - ${ZFS_ARC_MAX_GB}GB"
    echo ""
    
    # Confirm installation
    warning "This will DESTROY ALL DATA on $DISK"
    echo ""
    lsblk "$DISK" 2>/dev/null || true
    echo ""
    read -p "Type 'yes' to continue: " confirm
    if [[ "$confirm" != "yes" ]]; then
        error "Installation cancelled"
    fi
    
    # Run installation with error handling
    log "Starting installation process..."
    
    partition_disk "$DISK"
    
    # Format boot
    log "Formatting boot partition..."
    mkfs.vfat -F 32 -n BOOT "$BOOT_PART"
    
    create_zfs_pool "$DISK" "$ZFS_PART"
    mount_filesystems "$BOOT_PART"
    generate_config "$PLATFORM"
    create_backup "$DISK"
    install_system
    post_install
    
    # Final verification
    log "Running final verification..."
    if ! zpool status zroot &>/dev/null; then
        warning "ZFS pool not accessible after installation"
    fi
    
    # Summary
    echo ""
    success "Installation complete!"
    echo ""
    echo "System Information:"
    echo "  Platform: $PLATFORM"
    echo "  Disk: $DISK"
    echo "  Hostname: $HOSTNAME"
    echo "  Username: $USERNAME"
    echo "  ZFS Pool: $(zpool list -H -o health zroot 2>/dev/null || echo 'N/A')"
    echo ""
    echo "Next steps:"
    echo "  1. Reboot into the new system"
    echo "  2. Login as root"
    echo "  3. Run /root/post-install.sh"
    echo "  4. Login as $USERNAME with your new password"
    echo ""
    echo "Backup metadata saved to: /root/install-backup.json"
    echo ""
    echo "Enjoy your NixOS ZFS system!"
}

# Run main function
main "$@"