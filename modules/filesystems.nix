{
  config,
  lib,
  pkgs,
  ...
}: {
  boot.supportedFilesystems = [
    "ntfs"
    "exfat"
    "btrfs"
    "xfs"
    "zfs"
    "ext4"
    "vfat"
  ];

  environment.systemPackages = with pkgs;
    [
      ntfs3g
      exfatprogs
      xfsprogs
      btrfs-progs
      zfs
      apfsprogs
      gparted
      parted
      gnome.gnome-disk-utility
      ncdu
      duf
      diskus
      compsize
      testdisk
      photorec
      smartmontools
      nvme-cli
      fio
    ]
    ++ (import ../packages/filesystem-tools.nix {inherit pkgs;});

  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = ["/"];
  };
}
