# Filesystem and disk management tools
{pkgs, ...}:
with pkgs; [
  # Filesystem utilities
  ntfs3g
  exfatprogs
  xfsprogs
  btrfs-progs

  # Disk management
  gparted
  parted
  gnome-disk-utility

  # Analysis tools
  ncdu
  duf

  # File managers
  ranger # Terminal

  # Monitoring
  smartmontools
  nvme-cli
]
