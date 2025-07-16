# Hardware configuration for Btrfs-based system
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [(modulesPath + "/installer/scan/not-detected.nix")];

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
      # Btrfs snapshot entries
      systemd-boot.configurationLimit = 20;
    };

    # Use latest libre kernel (no proprietary blobs)
    kernelPackages = pkgs.linuxKernel.packages.linux_latest_libre;

    initrd = {
      availableKernelModules = ["xhci_pci" "ahci" "nvme" "usb_storage" "sd_mod" "virtio_pci" "virtio_blk"];
      kernelModules = ["btrfs"];
      supportedFilesystems = ["btrfs"];
    };

    # Kernel parameters optimized for Btrfs and performance
    kernelParams = [
      "threadirqs"
      "mitigations=off" # Performance over security (adjust based on needs)
      "nowatchdog"
      "quiet"
      "loglevel=3"
      "systemd.show_status=auto"
      "rd.udev.log_level=3"
    ];

    # Support for additional filesystems
    supportedFilesystems = ["ntfs" "exfat" "xfs" "zfs" "btrfs"];

    kernelModules = ["kvm-amd" "kvm-intel"];
    extraModulePackages = [];

    # Kernel sysctl optimizations
    kernel.sysctl = {
      # VM optimizations
      "vm.swappiness" = 10;
      "vm.vfs_cache_pressure" = 50;
      "vm.dirty_background_ratio" = 5;
      "vm.dirty_ratio" = 10;

      # Network optimizations
      "net.core.default_qdisc" = "cake";
      "net.ipv4.tcp_congestion" = "bbr";
      "net.ipv4.tcp_fastopen" = 3;

      # General optimizations
      "kernel.sysrq" = 1;
      "fs.file-max" = 2097152;
    };

    # Btrfs-specific boot settings
    postBootCommands = ''
      # Enable Btrfs automatic defragmentation for SSDs
      btrfs filesystem defragment -r -v -czstd /
    '';
  };

  # Filesystem configuration
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "btrfs";
      options = ["subvol=@" "compress=zstd:3" "noatime" "ssd" "space_cache=v2" "discard=async"];
    };

    "/home" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "btrfs";
      options = ["subvol=@home" "compress=zstd:3" "noatime" "ssd" "space_cache=v2" "discard=async"];
    };

    "/nix" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "btrfs";
      options = ["subvol=@nix" "compress=zstd:6" "noatime" "ssd" "space_cache=v2" "discard=async" "nodatacow"];
    };

    "/persist" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "btrfs";
      options = ["subvol=@persist" "compress=zstd:3" "noatime" "ssd" "space_cache=v2" "discard=async"];
    };

    "/var/log" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "btrfs";
      options = ["subvol=@log" "compress=zstd:1" "noatime" "ssd" "space_cache=v2" "discard=async"];
      neededForBoot = true;
    };

    "/var/cache" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "btrfs";
      options = ["subvol=@cache" "noatime" "ssd" "space_cache=v2" "discard=async" "nodatacow"];
    };

    "/.snapshots" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "btrfs";
      options = ["subvol=@snapshots" "compress=zstd:3" "noatime" "ssd" "space_cache=v2" "discard=async"];
    };

    "/swap" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "btrfs";
      options = ["subvol=@swap" "noatime" "nodatacow"];
    };

    "/boot" = {
      device = "/dev/disk/by-label/EFI";
      fsType = "vfat";
    };
  };

  # Swap configuration
  swapDevices = [
    {
      device = "/dev/disk/by-label/swap";
      priority = 100;
    }
  ];

  # Additional swap file on Btrfs (if needed)
  systemd.services.mkswapfile = {
    description = "Create Btrfs swapfile";
    wantedBy = ["swap-swapfile.swap"];
    serviceConfig.Type = "oneshot";
    script = ''
      if [ ! -f /swap/swapfile ]; then
        truncate -s 0 /swap/swapfile
        chattr +C /swap/swapfile
        btrfs property set /swap/swapfile compression none
        dd if=/dev/zero of=/swap/swapfile bs=1M count=4096
        chmod 600 /swap/swapfile
        mkswap /swap/swapfile
      fi
    '';
  };

  # Hardware configuration
  hardware = {
    enableRedistributableFirmware = false; # Using libre kernel
    graphics = {
      enable = true;
      extraPackages = with pkgs; [
        mesa.drivers
      ];
    };
  };

  # Services optimized for Btrfs
  services = {
    # Btrfs maintenance
    btrfs.autoScrub = {
      enable = true;
      interval = "weekly";
      fileSystems = ["/"];
    };

    # Periodic TRIM for SSDs
    fstrim = {
      enable = true;
      interval = "weekly";
    };

    # Snapshot management
    snapper = {
      configs = {
        home = {
          subvolume = "/home";
          extraConfig = ''
            TIMELINE_CREATE=yes
            TIMELINE_CLEANUP=yes
            TIMELINE_LIMIT_HOURLY=24
            TIMELINE_LIMIT_DAILY=7
            TIMELINE_LIMIT_WEEKLY=4
            TIMELINE_LIMIT_MONTHLY=12
            TIMELINE_LIMIT_YEARLY=2
          '';
        };
      };
    };
  };

  # Networking
  networking.hostId = lib.mkDefault "abcd1234";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Power management
  powerManagement = {
    enable = true;
    cpuFreqGovernor = "ondemand";
  };

  # Enable zram for better memory management
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };
}
