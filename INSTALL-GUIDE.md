# Installation Guide: Two-Stage Setup

This flake uses a two-stage installation approach to avoid conflicts with Chaotic Nyx during the initial system installation.

## Stage 1: Base System Installation

Install the base NixOS system with ZFS but without Chaotic Nyx packages:

```bash
# Use the base configuration (no Chaotic packages)
sudo nix --extra-experimental-features "nix-command flakes" run github:nix-community/disko -- --mode disko --flake .#nixos-dev

# Install the base system
sudo nixos-install --flake .#nixos-dev

# Reboot into the new system
sudo reboot
```

## Stage 2: Add Chaotic Nyx (After First Boot)

Once the base system is running, switch to the Chaotic-enhanced configuration:

```bash
# Switch to the Chaotic Nyx configuration
sudo nixos-rebuild switch --flake .#nixos-dev-chaotic
```

## Available Configurations

### Base Configurations (Stage 1)
- `nixos-dev` - Bare metal base system
- `nixos-qemu` - QEMU/KVM base system  
- `nixos-hyperv` - HyperV base system

### Chaotic Configurations (Stage 2)
- `nixos-dev-chaotic` - Bare metal with Chaotic Nyx
- `nixos-qemu-chaotic` - QEMU/KVM with Chaotic Nyx

## What's Included in Each Stage

### Stage 1 (Base)
- ✅ ZFS root filesystem
- ✅ Basic NixOS configuration
- ✅ Standard kernel
- ✅ Essential packages
- ✅ Steam and basic gaming support

### Stage 2 (Chaotic)
- 🔥 CachyOS kernel with BORE scheduler
- ⚡ sched-ext schedulers
- 🎮 Latest gaming tools (MangoHUD Git, Gamescope Git)
- 🛠️ Bleeding-edge development tools
- 📦 Binary cache for faster builds
- 🔧 HDR support (experimental)

## Why Two Stages?

The two-stage approach is necessary because:

1. **Disko compatibility**: Chaotic Nyx modules aren't available during the disko disk setup phase
2. **Installation reliability**: Base system installs more reliably without bleeding-edge packages
3. **Troubleshooting**: If Chaotic packages cause issues, you can easily roll back to the base configuration

## Troubleshooting

If you have issues with the Chaotic configuration:

```bash
# Roll back to base configuration
sudo nixos-rebuild switch --flake .#nixos-dev

# Or use previous generation
sudo nixos-rebuild switch --rollback
```

## Single-Stage Alternative

If you prefer to install everything at once (less reliable):

1. Edit `flake.nix` 
2. Add `chaotic.nixosModules.default` and `./chaotic-config.nix` to the base `nixos-dev` configuration
3. Use the installation steps from Stage 1

⚠️ **Note**: This approach may fail during disko execution due to missing Chaotic modules.