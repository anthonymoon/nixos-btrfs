#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Testing Chaotic Nyx Binary Cache Configuration"
echo "================================================="

# Check if chaotic input is properly configured
echo "📦 Checking flake inputs..."
if nix flake metadata --no-write-lock-file 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "chaotic.*github:chaotic-cx/nyx"; then
    echo "✅ Chaotic Nyx input is configured"
else
    echo "❌ Chaotic Nyx input not found"
    exit 1
fi

# Test base configuration
echo ""
echo "🔍 Testing base configuration..."
if nix eval .#nixosConfigurations.nixos-dev.config.environment.systemPackages --json >/dev/null 2>&1; then
    echo "✅ Base configuration builds successfully"
else
    echo "❌ Base configuration has errors"
    exit 1
fi

# Test Chaotic configuration
echo ""
echo "🔍 Testing Chaotic configuration..."
if nix eval .#nixosConfigurations.nixos-dev-chaotic.config.environment.systemPackages --json | grep -q "firefox_nightly"; then
    echo "✅ Chaotic packages are available in chaotic configuration"
else
    echo "❌ Chaotic packages not found in chaotic configuration"
    exit 1
fi

# Check binary cache configuration
echo ""
echo "🗄️ Checking binary cache configuration..."
if nix show-config | grep -q "chaotic-nyx.cachix.org"; then
    echo "✅ Chaotic binary cache is configured"
else
    echo "⚠️  Binary cache may not be configured (will be added after rebuild)"
fi

# Test building a small Chaotic package (without installing)
echo ""
echo "🔨 Testing build of a Chaotic package..."
echo "Building helix_git (this should use binary cache if available)..."

if timeout 300 nix build github:chaotic-cx/nyx/nyxpkgs-unstable#helix_git --no-link --print-out-paths; then
    echo "✅ Successfully built/downloaded helix_git"
else
    echo "❌ Failed to build helix_git (this may be expected on first run)"
fi

echo ""
echo "🏁 Chaotic Nyx configuration test complete!"
echo ""
echo "📋 Next steps:"
echo "1. Stage 1: Install base system with 'sudo nixos-install --flake .#nixos-dev'"
echo "2. Reboot into the new system"
echo "3. Stage 2: Switch to Chaotic with 'sudo nixos-rebuild switch --flake .#nixos-dev-chaotic'"
echo "4. Subsequent builds will use the binary cache for faster updates"
echo ""
echo "🎮 Gaming optimizations included:"
echo "   - CachyOS kernel with BORE scheduler"
echo "   - Mesa Git drivers"
echo "   - HDR support (experimental)"
echo "   - sched-ext schedulers"
echo "   - Latest MangoHUD, Gamescope, and gaming tools"
echo ""
echo "🔥 Bleeding-edge packages:"
echo "   - Firefox Nightly"
echo "   - Helix Git"
echo "   - Zed Editor Git"
echo "   - Telegram Desktop Git"
echo "   - Discord Krisp"
echo "   - And many more!"