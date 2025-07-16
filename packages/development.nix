# Development packages
{pkgs, ...}:
with pkgs; [
  # Editors
  vscode
  neovim

  # Version control
  git-crypt
  gh # GitHub CLI

  # Languages and runtimes
  python312
  python312Packages.pip
  python312Packages.virtualenv
  nodejs_20
  rustup
  go

  # Cloud and DevOps
  terraform
  google-cloud-sdk
  kubectl
  kubernetes-helm
  docker-compose

  # Build tools
  gnumake
  cmake
  pkg-config

  # Development utilities
  jq # JSON processor
  yq # YAML processor
  direnv
  pre-commit
]
