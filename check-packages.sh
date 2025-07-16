#!/usr/bin/env bash
# Script to validate all packages exist in nixpkgs

echo "Checking package availability..."

check_packages() {
    local file=$1
    echo "Checking $file..."
    
    # Extract package names (simple grep for now)
    grep -E "^\s*[a-zA-Z0-9_-]+\s*$" "$file" | while read -r pkg; do
        pkg=$(echo "$pkg" | xargs) # trim whitespace
        if [[ -n "$pkg" && "$pkg" != "#"* ]]; then
            if ! nix-instantiate '<nixpkgs>' -A "$pkg" &>/dev/null; then
                echo "  ❌ $pkg - NOT FOUND"
            else
                echo "  ✓ $pkg"
            fi
        fi
    done
}

# Check all package files
for f in packages/*.nix; do
    check_packages "$f"
done

echo ""
echo "To test the full config:"
echo "  nix flake check"
echo "  nix build .#nixosConfigurations.nixos.config.system.build.toplevel"