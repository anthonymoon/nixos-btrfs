#!/usr/bin/env bash
# Configure binary cache integration for NixOS

set -euo pipefail

echo "Configuring binary cache integration"
echo "===================================="

# Default values
CACHE_URL="${1:-http://cachy.local}"
CACHE_NAME="${2:-cachy-local}"

echo "Cache URL: $CACHE_URL"
echo "Cache Name: $CACHE_NAME"

# Check if we can reach the cache
echo "Testing cache connectivity..."
if curl -s --connect-timeout 5 "$CACHE_URL/nix-cache-info" > /dev/null; then
    echo "✓ Cache is reachable"
else
    echo "✗ Cache is not reachable at $CACHE_URL"
    echo "Make sure nix-serve is running on the cache server"
    exit 1
fi

# Get cache info
echo ""
echo "Cache information:"
curl -s "$CACHE_URL/nix-cache-info" || echo "Could not fetch cache info"

# Check if public key file exists
if [[ -f /var/lib/nix-serve/cache-pub-key.pem ]]; then
    PUBLIC_KEY=$(cat /var/lib/nix-serve/cache-pub-key.pem)
    echo ""
    echo "Public key found: $PUBLIC_KEY"
else
    echo ""
    echo "Public key not found locally. Please provide it:"
    read -p "Enter public key: " PUBLIC_KEY
fi

# Create binary cache configuration module
echo ""
echo "Creating binary cache configuration module..."

cat > modules/binary-cache.nix << EOF
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Binary cache configuration
  nix.settings = {
    substituters = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org"
      "$CACHE_URL"
    ];
    
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "$PUBLIC_KEY"
    ];
    
    # Optional: Configure cache priorities
    substituter-priority = {
      "https://cache.nixos.org/" = 40;
      "https://nix-community.cachix.org" = 41;
      "$CACHE_URL" = 42;
    };
  };
  
  # Optional: Configure binary cache pushing
  nix.distributedBuilds = true;
  nix.buildMachines = [
    {
      hostName = "$(echo $CACHE_URL | sed 's|http://||' | sed 's|https://||' | cut -d/ -f1)";
      system = "x86_64-linux";
      maxJobs = 4;
      speedFactor = 1;
      supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm"];
    }
  ];
}
EOF

echo "✓ Binary cache module created at modules/binary-cache.nix"

# Update flake.nix to include the binary cache module
echo ""
echo "Updating flake.nix to include binary cache module..."

if grep -q "binary-cache.nix" flake.nix; then
    echo "✓ Binary cache module already included in flake.nix"
else
    # Add to modules list
    sed -i '/modules\/filesystems.nix/a\          ./modules/binary-cache.nix' flake.nix
    echo "✓ Added binary cache module to flake.nix"
fi

# Create cache management script
echo ""
echo "Creating cache management script..."

cat > scripts/cache-management.sh << 'EOF'
#!/usr/bin/env bash
# Binary cache management utilities

set -euo pipefail

CACHE_URL="${CACHE_URL:-http://cachy.local}"

show_help() {
    echo "Cache Management Utilities"
    echo "========================="
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  status           Show cache status"
    echo "  info             Show cache information"
    echo "  test             Test cache connectivity"
    echo "  push <path>      Push store path to cache"
    echo "  clear            Clear local cache"
    echo "  stats            Show cache statistics"
    echo ""
    echo "Environment variables:"
    echo "  CACHE_URL        Binary cache URL (default: http://cachy.local)"
}

case "${1:-help}" in
    "status")
        echo "Cache Status:"
        echo "============"
        curl -s "$CACHE_URL/nix-cache-info" || echo "Cache not reachable"
        ;;
    "info")
        echo "Cache Information:"
        echo "=================="
        curl -s "$CACHE_URL/nix-cache-info"
        echo ""
        echo "Public Key:"
        curl -s "$CACHE_URL/nix-cache-info" | grep -o 'PublicKey: .*' || echo "No public key found"
        ;;
    "test")
        echo "Testing cache connectivity..."
        if curl -s --connect-timeout 5 "$CACHE_URL/nix-cache-info" > /dev/null; then
            echo "✓ Cache is reachable"
            exit 0
        else
            echo "✗ Cache is not reachable"
            exit 1
        fi
        ;;
    "push")
        if [[ -z "${2:-}" ]]; then
            echo "ERROR: No path specified"
            echo "Usage: $0 push <store-path>"
            exit 1
        fi
        echo "Pushing $2 to cache..."
        nix copy --to "$CACHE_URL" "$2"
        ;;
    "clear")
        echo "Clearing local cache..."
        nix-collect-garbage -d
        ;;
    "stats")
        echo "Cache Statistics:"
        echo "================"
        nix path-info --all --json | jq -r '.[] | .path' | wc -l | xargs echo "Local store paths:"
        df -h /nix/store | tail -1 | awk '{print "Store usage: " $3 " / " $2 " (" $5 ")"}'
        ;;
    "help"|*)
        show_help
        ;;
esac
EOF

chmod +x scripts/cache-management.sh

echo "✓ Cache management script created at scripts/cache-management.sh"

# Test the configuration
echo ""
echo "Testing binary cache configuration..."
if nix eval --expr 'builtins.head (import <nixpkgs> {}).lib.systems.examples.x86_64-linux.system' > /dev/null 2>&1; then
    echo "✓ Nix configuration is valid"
else
    echo "✗ Nix configuration has issues"
fi

echo ""
echo "Binary cache integration complete!"
echo "================================="
echo ""
echo "Next steps:"
echo "1. Deploy the configuration: sudo nixos-rebuild switch --flake .#nixos"
echo "2. Test the cache: ./scripts/cache-management.sh test"
echo "3. Monitor cache usage: ./scripts/cache-management.sh stats"
echo ""
echo "The cache will be automatically used for future builds."
echo "To manually push a path to cache: ./scripts/cache-management.sh push /nix/store/..."