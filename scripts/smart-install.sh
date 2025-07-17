#!/usr/bin/env bash
set -euo pipefail

# Smart NixOS installer that handles space issues automatically

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Parse arguments
HOST="${1:-vm}"
DISK="${2:-}"
FLAKE="${3:-github:anthonymoon/nixos-btrfs}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║               Smart NixOS Installer (Space-Aware)            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check if we have enough space
AVAILABLE_SPACE=$(df -BG /nix/store 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//' || echo "0")
print_info "Available space in /nix/store: ${AVAILABLE_SPACE}GB"

if [[ $AVAILABLE_SPACE -lt 8 ]]; then
    print_warning "Limited space detected. Using smart installation method..."
    
    # Method 1: Try to use nixos-anywhere if available
    if command -v nix >/dev/null 2>&1; then
        print_info "Attempting nixos-anywhere installation (handles space efficiently)..."
        
        # First, partition the disk with disko
        if [[ -n "$DISK" ]]; then
            print_info "Partitioning disk with disko..."
            
            # Use disko to partition
            if sudo nix run \
                --extra-experimental-features 'nix-command flakes' \
                --no-write-lock-file \
                ${FLAKE}#disko -- \
                --mode destroy,format,mount \
                --flake "${FLAKE}#${HOST}" \
                --arg device "\"${DISK}\"" 2>&1 | tee /tmp/disko.log; then
                
                print_success "Disk partitioned successfully"
                
                # Now install using nixos-install which uses the mounted filesystem
                print_info "Installing NixOS to mounted filesystem..."
                
                # Create minimal configuration to bootstrap
                sudo mkdir -p /mnt/etc/nixos
                
                # Generate hardware config
                sudo nixos-generate-config --root /mnt || true
                
                # Install using the flake
                if sudo nixos-install \
                    --flake "${FLAKE}#${HOST}" \
                    --root /mnt \
                    --no-root-password \
                    --no-channel-copy \
                    --max-jobs 4 \
                    --cores 2 \
                    --option binary-caches "https://cache.nixos.org" \
                    --option require-sigs false \
                    --option substituters "https://cache.nixos.org" \
                    --option extra-substituters "" \
                    --show-trace 2>&1 | tee /tmp/nixos-install.log; then
                    
                    print_success "Installation completed!"
                    print_info "You can now reboot into your new system"
                else
                    print_error "Installation failed. Check /tmp/nixos-install.log"
                    exit 1
                fi
            else
                print_error "Disk partitioning failed. Check /tmp/disko.log"
                exit 1
            fi
        else
            print_error "No disk specified for limited space installation"
            exit 1
        fi
    else
        print_error "Nix not available"
        exit 1
    fi
else
    # Enough space, use the standard method
    print_info "Sufficient space available. Using standard installation..."
    exec sudo nix run \
        --extra-experimental-features 'nix-command flakes' \
        --no-write-lock-file \
        ${FLAKE}#disko-install -- \
        "$HOST" "$DISK"
fi