# Base system packages - minimal essentials
{pkgs, ...}:
with pkgs; [
  # Core utilities
  coreutils
  git
  vim
  wget
  curl

  # Essential terminal tools
  htop
  eza # Better ls
  fd # Better find
  ripgrep # Better grep
  bat # Better cat

  # Compression
  zip
  unzip
  p7zip

  # Network basics
  dig
  traceroute
  nmap
]
