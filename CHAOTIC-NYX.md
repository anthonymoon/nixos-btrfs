# Chaotic Nyx Integration Guide

This flake is now enhanced with **Chaotic Nyx** - providing bleeding-edge packages and experimental modules for "too much bleeding-edge" enthusiasts! 🚀

## What is Chaotic Nyx?

Chaotic Nyx is a Nix flake from the Chaotic Linux User Group that provides:

- 🔥 **Bleeding-edge packages**: mesa_git, linux_cachyos, firefox_nightly, gamescope_git
- ⚡ **Performance optimizations**: CachyOS kernels, sched-ext schedulers  
- 🎮 **Gaming enhancements**: Latest MangoHUD, Proton CachyOS, HDR support
- 🧪 **Experimental modules**: HDR, DuckDNS, advanced schedulers
- 📦 **Binary cache**: Pre-built packages for faster builds

## Features Enabled

### 🏗️ System-Level Enhancements

- **CachyOS Kernel**: `linuxPackages_cachyos` with BORE scheduler
- **sched-ext Schedulers**: Modern CPU schedulers (`scx_rustland`, `scx_rusty`)
- **Ananicy Rules**: Automatic process priority optimization
- **Mesa Git**: Latest GPU drivers with better performance
- **HDR Support**: Experimental HDR module for AMD GPUs

### 🎮 Gaming Optimizations

- **Gamescope Git**: Latest SteamOS compositor
- **MangoHUD Git**: Latest performance overlay
- **Proton CachyOS**: Optimized Wine/Proton builds
- **Discord Krisp**: Discord with noise suppression
- **Luxtorpeda**: Native Linux game engines

### 🛠️ Development Tools

- **Helix Git**: Post-modern modal text editor
- **Zed Editor Git**: High-performance multiplayer editor  
- **Firefox Nightly**: Latest web technologies
- **Telegram Desktop Git**: Latest features

## Binary Cache

The binary cache is automatically configured and provides:

- ✅ **x86_64-linux** (primary)
- ✅ **aarch64-linux** 
- ✅ **aarch64-darwin**

Cache URL: `https://chaotic-nyx.cachix.org/`

## Platform Configurations

### 🖥️ Bare Metal (`nixos-dev`)
- Full Chaotic Nyx integration
- AMD GPU optimizations with Mesa Git
- Gaming performance packages
- HDR support

### 🖥️ QEMU/KVM (`nixos-qemu`)  
- VM-optimized Chaotic packages
- Mesa Git for better virtualized graphics
- Gaming tools for VM gaming

### 🖥️ HyperV (`nixos-hyperv`)
- Conservative configuration (no Chaotic for compatibility)
- Stable packages only

## Testing the Configuration

Run the test script to verify everything is working:

```bash
./test-chaotic-cache.sh
```

## Building the System

```bash
# Apply the new configuration
sudo nixos-rebuild switch --flake .#nixos-dev

# Build ISO with Chaotic packages
nix build .#iso

# Build QEMU image
nix build .#qemu-image
```

## Available Packages

### 🎮 Gaming
- `gamescope_git` - SteamOS session compositor
- `mangohud_git` - Performance overlay 
- `proton-cachyos` - Optimized Wine/Proton
- `discord-krisp` - Discord with noise suppression
- `luxtorpeda` - Native Linux game engines

### 🌐 Browsers  
- `firefox_nightly` - Latest Firefox features
- `firedragon` - Floorp fork with custom branding

### 💻 Development
- `helix_git` - Post-modern modal editor
- `zed-editor_git` - High-performance multiplayer editor
- `nix_git` - Latest Nix features

### 🗣️ Communication
- `telegram-desktop_git` - Latest Telegram features

### 🔧 System Tools
- `linux_cachyos` - CachyOS kernel with optimizations
- `scx_git.full` - sched-ext schedulers
- `ananicy-rules-cachyos_git` - Process priority rules
- `openrgb_git` - RGB lighting control
- `pwvucontrol_git` - PipeWire volume control

## Kernel Options

### Standard CachyOS Kernel
```nix
boot.kernelPackages = pkgs.linuxPackages_cachyos;
```

### With Microarchitecture Optimization
```nix
boot.kernelPackages = pkgs.linuxPackages_cachyos.cachyOverride { 
  mArch = "GENERIC_V3";  # V2, V3, V4, or ZEN4
};
```

### Other Variants
- `linuxPackages_cachyos-lto` - Built with LLVM and Thin LTO
- `linuxPackages_cachyos-hardened` - Security-hardened version
- `linuxPackages_cachyos-server` - Server-optimized
- `linuxPackages_cachyos-rc` - Release candidate versions

## Scheduler Configuration

The system uses sched-ext schedulers for better performance:

```nix
services.scx = {
  enable = true;
  scheduler = "scx_rustland";  # Options: scx_rusty, scx_lavd, scx_bpfland
  package = pkgs.scx_git.full;
};
```

Check scheduler status:
```bash
systemctl status scx.service
sudo scx_rusty  # Manual scheduler start
```

## HDR Support

Experimental HDR support is enabled:

```nix
chaotic.hdr.enable = true;
chaotic.hdr.wsiPackage = pkgs.gamescope-wsi_git;
```

## Troubleshooting

### Cache Issues
If builds are slow, verify cache configuration:
```bash
nix show-config | grep chaotic
curl -L 'https://chaotic-nyx.cachix.org/[HASH].narinfo'
```

### Kernel Building
If the kernel rebuilds instead of using cache:
```bash
nix eval .#nixosConfigurations.nixos-dev.config.boot.kernelPackages.kernel.outPath
nix eval 'github:chaotic-cx/nyx/nyxpkgs-unstable#linuxPackages_cachyos.kernel.outPath'
```

Hashes should match for cache hits.

## Support

- 📖 **Documentation**: https://chaotic-cx.github.io/nyx/
- 🐛 **Issues**: https://github.com/chaotic-cx/nyx/issues  
- 💬 **Matrix**: #chaotic-nyx:ubiquelambda.dev
- 📱 **Telegram**: Chaotic-AUR group

## Notes

- ⚠️  Some packages are marked as "unstable" - they're bleeding-edge!
- 🔄 Updates happen frequently via the rolling release model
- 🎯 Perfect for enthusiasts who want the latest and greatest
- 🚀 Significant performance improvements for gaming and development

Enjoy your bleeding-edge NixOS experience! 🔥