# Filesystem and disk management tools
{pkgs, ...}:
with pkgs; [
  # Filesystem utilities
  ntfs3g
  exfatprogs
  xfsprogs
  btrfs-progs
  zfstools
  apfsprogs

  # Disk management
  gparted
  parted
  gnome.gnome-disk-utility

  # Analysis tools
  ncdu
  duf
  diskus
  compsize

  # File managers
  ranger # Terminal
  mc # Midnight Commander

  # Recovery tools
  testdisk
  photorec

  # Monitoring
  smartmontools
  nvme-cli

  # Benchmarking
  fio
]
