#!/usr/bin/env bash
set -euo pipefail

# Smart NixOS installer - just delegates to disko-install

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                   Smart NixOS Installer                      ║"
echo "║                  (Handles space automatically)               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Delegate to disko-install which handles everything properly
exec nix run \
  --extra-experimental-features nix-command \
  --extra-experimental-features flakes \
  github:anthonymoon/nixos-btrfs#disko-install -- "$@"