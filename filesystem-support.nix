# Comprehensive filesystem support
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Enable filesystem support
  boot.supportedFilesystems = [
    "ntfs"
    "ntfs3" # Newer NTFS driver with better performance
    "exfat"
    "xfs"
    "zfs"
    "btrfs"
    "ext4"
    "vfat"
    "f2fs"
  ];

  # APFS support (read-only for now)
  boot.extraModulePackages = with config.boot.kernelPackages; [
    apfs
  ];

  # Filesystem utilities
  environment.systemPackages = with pkgs; [
    # NTFS
    ntfs3g
    ntfsprogs

    # exFAT
    exfatprogs

    # XFS
    xfsprogs
    xfsdump

    # ZFS
    zfs
    zfstools

    # APFS
    apfsprogs
    apfs-fuse

    # Btrfs
    btrfs-progs
    compsize

    # Generic filesystem tools
    gparted
    parted
    gnome.gnome-disk-utility
    diskus # Fast disk usage analyzer
    duf # Better df alternative
    ncdu # NCurses disk usage

    # Recovery and forensics
    testdisk
    photorec
    extundelete

    # Filesystem conversion
    fuse-overlayfs
    mergerfs

    # Encryption support
    cryptsetup

    # Disk health monitoring
    smartmontools
    hdparm
    nvme-cli

    # Benchmarking
    fio
    iozone
    bonnie
  ];

  # Enable FUSE for userspace filesystem support
  programs.fuse.userAllowOther = true;

  # Services for filesystem management
  services = {
    # Enable SMART monitoring
    smartd = {
      enable = true;
      autodetect = true;
      notifications = {
        wall.enable = true;
      };
    };

    # Enable automatic mounting of removable media
    devmon.enable = true;

    # Enable udisks2 for desktop environments
    udisks2.enable = true;

    # Enable gvfs for better filesystem integration
    gvfs.enable = true;
  };

  # Kernel parameters for better filesystem performance
  boot.kernelParams = [
    # Better I/O scheduling for SSDs
    "scsi_mod.use_blk_mq=1"

    # NTFS-3G performance
    "ntfs3.acl=1"
  ];

  # Sysctl settings for filesystem performance
  boot.kernel.sysctl = {
    # Increase inotify limits for file watching
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 512;

    # Better dirty page handling
    "vm.dirty_ratio" = 10;
    "vm.dirty_background_ratio" = 5;

    # Increase file handle limits
    "fs.file-max" = 2097152;
    "fs.nr_open" = 1048576;
  };

  # Mount options for better performance
  fileSystems = {
    # Example NTFS mount with optimal settings
    # "/mnt/windows" = {
    #   device = "/dev/disk/by-label/Windows";
    #   fsType = "ntfs3";
    #   options = [
    #     "rw"
    #     "uid=1000"
    #     "gid=100"
    #     "dmask=022"
    #     "fmask=133"
    #     "windows_names"
    #     "iocharset=utf8"
    #     "prealloc"
    #   ];
    # };
  };

  # Auto-mount configuration for common filesystems
  services.udev.extraRules = ''
    # Auto-mount NTFS drives with proper permissions
    ENV{ID_FS_TYPE}=="ntfs", ENV{ID_FS_TYPE}="ntfs3"

    # Better handling of exFAT
    ACTION=="add", KERNEL=="sd[a-z][0-9]", ENV{ID_FS_TYPE}=="exfat", RUN+="${pkgs.systemd}/bin/systemctl start mount-exfat@%k.service"
  '';

  # Aliases for filesystem management
  environment.shellAliases = {
    # Disk usage
    duf = "duf -theme ansi";
    ncdu = "ncdu --color dark";

    # Filesystem info
    lsfs = "findmnt -D";
    fsinfo = "df -Th | grep -v tmpfs | grep -v loop";

    # SMART status
    smartcheck = "sudo smartctl -a";

    # Quick filesystem benchmarks
    diskbench = "fio --name=rand_rw --ioengine=libaio --rw=randrw --bs=4k --numjobs=4 --size=1G --runtime=30 --group_reporting";
  };
}
