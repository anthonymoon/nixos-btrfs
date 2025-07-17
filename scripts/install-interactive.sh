#!/usr/bin/env bash
# Interactive NixOS installation script with disko
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
if [[ $EUID -eq 0 ]]; then
    log_error "This script should not be run as root"
    log_info "Run as regular user, it will prompt for sudo when needed"
    exit 1
fi

# Check if we're in the right directory
if [[ ! -f "flake.nix" ]]; then
    log_error "flake.nix not found. Please run this script from the repository root."
    exit 1
fi

# Banner
echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                   NixOS Disko Installer                     ║"
echo "║              Multi-host automated installation              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Safety warning
echo -e "${RED}WARNING: This will COMPLETELY ERASE the selected disk!${NC}"
echo -e "${YELLOW}Make sure you have backups of any important data.${NC}"
echo ""

# List available hosts
log_step "Detecting available hosts..."
available_hosts=$(nix eval --json '.#nixosConfigurations' --apply 'builtins.attrNames' 2>/dev/null | jq -r '.[]' | sort)

if [[ -z "$available_hosts" ]]; then
    log_error "No NixOS configurations found in flake"
    exit 1
fi

echo "Available hosts:"
i=1
declare -a host_array
while IFS= read -r host; do
    echo "  $i) $host"
    host_array[$i]="$host"
    ((i++))
done <<< "$available_hosts"

echo ""
read -p "Select host number (1-$((i-1))): " host_num

# Validate selection
if [[ ! "$host_num" =~ ^[0-9]+$ ]] || [[ $host_num -lt 1 ]] || [[ $host_num -gt $((i-1)) ]]; then
    log_error "Invalid selection"
    exit 1
fi

selected_host="${host_array[$host_num]}"
log_info "Selected host: $selected_host"

# Detect disko configuration type
log_step "Analyzing host configuration..."
config_file="hosts/$selected_host/configuration.nix"
if [[ ! -f "$config_file" ]]; then
    log_warn "Host configuration file not found at $config_file"
    log_info "Continuing with flake configuration detection..."
fi

# Try to detect disk configuration type
disk_config_type="unknown"
if nix eval ".#nixosConfigurations.$selected_host.config.system.boot.filesystem" 2>/dev/null | grep -q "zfs"; then
    disk_config_type="zfs"
elif nix eval ".#nixosConfigurations.$selected_host" --apply 'x: x.config.boot.supportedFilesystems' 2>/dev/null | grep -q "zfs"; then
    disk_config_type="zfs"
elif nix eval ".#nixosConfigurations.$selected_host" --apply 'x: x.config.boot.initrd.luks.devices' 2>/dev/null | grep -q "root"; then
    disk_config_type="btrfs-luks"
else
    disk_config_type="btrfs"
fi

log_info "Detected disk configuration: $disk_config_type"

# Auto-detect primary disk
log_step "Auto-detecting primary disk..."
detected_disk=""
if command -v lsblk >/dev/null 2>&1; then
    # Detect suitable disks
    suitable_disks=$(lsblk -dpno NAME,SIZE,TYPE,TRAN,ROTA | awk '
        $3 == "disk" && $1 !~ /loop|ram/ {
            size_gb = int($2 / 1073741824)
            if (size_gb >= 20) {
                score = size_gb
                if ($4 == "nvme") score += 10000
                if ($5 == "0") score += 1000  # SSD
                print score, $1
            }
        }
    ' | sort -nr | head -5)
    
    if [[ -n "$suitable_disks" ]]; then
        echo "Detected suitable disks:"
        echo "$suitable_disks" | while read score disk; do
            size=$(lsblk -dpno SIZE "$disk" 2>/dev/null | head -1)
            type=$(lsblk -dpno TRAN "$disk" 2>/dev/null | head -1)
            rota=$(lsblk -dpno ROTA "$disk" 2>/dev/null | head -1)
            type_desc="HDD"
            [[ "$rota" == "0" ]] && type_desc="SSD"
            [[ "$type" == "nvme" ]] && type_desc="NVMe"
            echo "  $disk ($size, $type_desc)"
        done
        
        detected_disk=$(echo "$suitable_disks" | head -1 | awk '{print $2}')
        log_info "Auto-detected primary disk: $detected_disk"
    fi
fi

# Disk selection
echo ""
log_step "Disk selection"
if [[ -n "$detected_disk" ]]; then
    echo "Auto-detected disk: $detected_disk"
    read -p "Use this disk? [Y/n] " -n 1 -r use_detected
    echo ""
    if [[ $use_detected =~ ^[Nn]$ ]]; then
        detected_disk=""
    fi
fi

if [[ -z "$detected_disk" ]]; then
    echo "Available disks:"
    lsblk -dpno NAME,SIZE,TYPE,MODEL | grep -E "disk" | head -10
    echo ""
    read -p "Enter disk path (e.g., /dev/sda): " detected_disk
fi

# Validate disk
if [[ ! -b "$detected_disk" ]]; then
    log_error "Invalid disk: $detected_disk"
    exit 1
fi

# Show disk information
log_info "Target disk information:"
lsblk "$detected_disk" || true
echo ""
if command -v smartctl >/dev/null 2>&1; then
    sudo smartctl -i "$detected_disk" 2>/dev/null | grep -E "Model|Capacity|Form Factor" || true
    echo ""
fi

# For ZFS mirror, detect second disk
second_disk=""
if [[ "$disk_config_type" == "zfs" ]] && nix eval ".#nixosConfigurations.$selected_host.config.disko.mirrorDisks" 2>/dev/null | grep -q "2"; then
    log_step "ZFS mirror detected - selecting second disk"
    echo "Available disks (excluding $detected_disk):"
    lsblk -dpno NAME,SIZE,TYPE,MODEL | grep -E "disk" | grep -v "$detected_disk" | head -10
    echo ""
    read -p "Enter second disk path for mirror: " second_disk
    
    if [[ ! -b "$second_disk" ]]; then
        log_error "Invalid second disk: $second_disk"
        exit 1
    fi
    
    if [[ "$second_disk" == "$detected_disk" ]]; then
        log_error "Second disk cannot be the same as first disk"
        exit 1
    fi
fi

# Encryption password (for LUKS configurations)
encryption_password=""
if [[ "$disk_config_type" == "btrfs-luks" ]]; then
    log_step "LUKS encryption setup"
    echo "This configuration uses LUKS encryption."
    echo "You'll need to set an encryption password."
    echo ""
    
    while true; do
        read -s -p "Enter encryption password: " encryption_password
        echo ""
        read -s -p "Confirm encryption password: " encryption_password_confirm
        echo ""
        
        if [[ "$encryption_password" == "$encryption_password_confirm" ]]; then
            break
        else
            log_error "Passwords do not match. Please try again."
        fi
    done
    
    if [[ ${#encryption_password} -lt 8 ]]; then
        log_warn "Password is shorter than 8 characters. Consider using a stronger password."
        read -p "Continue anyway? [y/N] " -n 1 -r weak_password
        echo ""
        if [[ ! $weak_password =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

# Final confirmation
log_step "Installation summary"
echo "Host: $selected_host"
echo "Disk configuration: $disk_config_type"
echo "Primary disk: $detected_disk"
[[ -n "$second_disk" ]] && echo "Second disk: $second_disk"
[[ "$disk_config_type" == "btrfs-luks" ]] && echo "Encryption: Enabled (LUKS2 + TPM2)"
echo ""
echo -e "${RED}This will COMPLETELY ERASE the selected disk(s)!${NC}"
read -p "Type 'yes' to continue: " final_confirmation

if [[ "$final_confirmation" != "yes" ]]; then
    log_info "Installation cancelled"
    exit 0
fi

# Start installation
log_step "Starting installation..."

# Unmount any existing mounts on target disk
log_info "Unmounting any existing filesystems..."
sudo umount "${detected_disk}"* 2>/dev/null || true
[[ -n "$second_disk" ]] && sudo umount "${second_disk}"* 2>/dev/null || true

# Build disko command
disko_cmd="sudo nix --extra-experimental-features 'nix-command flakes' run github:nix-community/disko#disko-install -- --flake .#$selected_host"

# Add disk overrides if needed
if [[ "$disk_config_type" == "zfs" ]] && [[ -n "$second_disk" ]]; then
    disko_cmd="$disko_cmd --disk disk1 $detected_disk --disk disk2 $second_disk"
else
    disko_cmd="$disko_cmd --disk main $detected_disk"
fi

# Add other options
disko_cmd="$disko_cmd --write-efi-boot-entries"

log_info "Running disko installation command:"
echo "$disko_cmd"
echo ""

# Set up LUKS password if needed
if [[ "$disk_config_type" == "btrfs-luks" ]] && [[ -n "$encryption_password" ]]; then
    # Create a temporary password file
    password_file=$(mktemp)
    echo "$encryption_password" > "$password_file"
    chmod 600 "$password_file"
    
    # Export for cryptsetup
    export CRYPTSETUP_PASSWORD_FILE="$password_file"
    
    # Clean up password after installation
    trap "rm -f '$password_file'" EXIT
fi

# Run the installation
if $disko_cmd; then
    log_info "Disko installation completed successfully!"
    
    # Post-installation steps
    log_step "Post-installation setup"
    
    # Copy the flake to the new system
    if [[ -d "/mnt/etc/nixos" ]]; then
        log_info "Copying flake configuration to new system..."
        sudo cp -r . /mnt/etc/nixos/ || log_warn "Failed to copy flake"
    fi
    
    # Set up TPM2 LUKS unlock (for encrypted systems)
    if [[ "$disk_config_type" == "btrfs-luks" ]]; then
        log_info "TPM2 auto-unlock can be set up after first boot"
        log_info "Run: setup-tpm2-luks"
    fi
    
    # Final instructions
    echo ""
    log_info "Installation completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Reboot into your new system: sudo reboot"
    echo "2. Set user password: passwd <username>"
    if [[ "$disk_config_type" == "btrfs-luks" ]]; then
        echo "3. Set up TPM2 auto-unlock: setup-tpm2-luks"
    fi
    echo "4. Update system: sudo nixos-rebuild switch --flake /etc/nixos#$selected_host"
    echo ""
    echo "System configuration: /etc/nixos"
    echo "Rebuild command: sudo nixos-rebuild switch --flake .#$selected_host"
    
else
    log_error "Installation failed!"
    exit 1
fi