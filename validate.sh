#!/usr/bin/env bash
# Manual validation script for when skipping pre-commit checks

set -euo pipefail

echo "Running NixOS configuration validation..."
echo ""

# Format check
echo "1. Checking formatting with Alejandra..."
if alejandra --check . &>/dev/null; then
    echo "   ✓ Formatting is correct"
else
    echo "   ✗ Formatting issues found. Run: alejandra ."
    exit 1
fi

# Flake check
echo "2. Running flake check..."
if nix flake check --no-write-lock-file; then
    echo "   ✓ Flake check passed"
else
    echo "   ✗ Flake check failed"
    exit 1
fi

# Eval check
echo "3. Checking configuration evaluation..."
if nix eval .#nixosConfigurations.nixos.config.system.build.toplevel.drvPath --no-write-lock-file >/dev/null; then
    echo "   ✓ Configuration evaluates successfully"
else
    echo "   ✗ Configuration evaluation failed"
    exit 1
fi

echo ""
echo "All checks passed! ✓"