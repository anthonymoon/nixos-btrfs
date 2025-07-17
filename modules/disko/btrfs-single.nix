{
  config,
  lib,
  pkgs,
  ...
}: let
  # Import disk detection utilities
  diskLib = import ../../lib/disk-detection.nix {inherit lib pkgs;};

  # Auto-detect the primary disk at evaluation time
  primaryDisk = config.disko.primaryDisk or diskLib.detectPrimaryDisk {
    preferNvme = true;
    preferSSD = true;
    minSizeGB = 20;
  };
in {
  options.disko = {
    primaryDisk = lib.mkOption {
      type = lib.types.str;
      default = primaryDisk;
      description = "Primary disk to use for installation (auto-detected if not specified)";
    };
  };

  config = {
    # Set filesystem type for system modules
    system.boot.filesystem = "btrfs";

    disko.devices = {
      disk = {
        main = {
          device = config.disko.primaryDisk;
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                priority = 1;
                name = "ESP";
                size = "1G";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [
                    "umask=0077"
                    "defaults"
                    "noatime"
                    "nodiratime"
                  ];
                };
              };
              root = {
                priority = 2;
                name = "root";
                size = "100%";
                content = {
                  type = "btrfs";
                  extraArgs = ["-f"];
                  # BTRFS optimizations for modern SSDs/NVMe
                  mountOptions = [
                    "compress=zstd:3"
                    "noatime"
                    "nodiratime"
                    "ssd"
                    "space_cache=v2"
                    "discard=async"
                    "autodefrag"
                    "thread_pool=8"
                  ];
                  subvolumes = {
                    # Root subvolume
                    "@" = {
                      mountpoint = "/";
                      mountOptions = [
                        "compress=zstd:3"
                        "noatime"
                        "nodiratime"
                        "ssd"
                        "space_cache=v2"
                        "discard=async"
                        "autodefrag"
                        "thread_pool=8"
                      ];
                    };

                    # Home directory subvolume
                    "@home" = {
                      mountpoint = "/home";
                      mountOptions = [
                        "compress=zstd:3"
                        "noatime"
                        "nodiratime"
                        "ssd"
                        "space_cache=v2"
                        "discard=async"
                        "autodefrag"
                        "thread_pool=8"
                      ];
                    };

                    # Nix store subvolume - higher compression for better deduplication
                    "@nix" = {
                      mountpoint = "/nix";
                      mountOptions = [
                        "compress=zstd:6"
                        "noatime"
                        "nodiratime"
                        "ssd"
                        "space_cache=v2"
                        "discard=async"
                        "thread_pool=8"
                      ];
                    };

                    # Variable data subvolume
                    "@var" = {
                      mountpoint = "/var";
                      mountOptions = [
                        "compress=zstd:3"
                        "noatime"
                        "nodiratime"
                        "ssd"
                        "space_cache=v2"
                        "discard=async"
                        "autodefrag"
                        "thread_pool=8"
                      ];
                    };

                    # Temporary files - lighter compression for performance
                    "@tmp" = {
                      mountpoint = "/tmp";
                      mountOptions = [
                        "compress=zstd:1"
                        "noatime"
                        "nodiratime"
                        "ssd"
                        "space_cache=v2"
                        "discard=async"
                        "thread_pool=8"
                      ];
                    };

                    # Snapshots subvolume
                    "@snapshots" = {
                      mountpoint = "/.snapshots";
                      mountOptions = [
                        "compress=zstd:3"
                        "noatime"
                        "nodiratime"
                        "ssd"
                        "space_cache=v2"
                        "discard=async"
                        "thread_pool=8"
                      ];
                    };

                    # Docker/containers subvolume (if using containers)
                    "@docker" = {
                      mountpoint = "/var/lib/docker";
                      mountOptions = [
                        "compress=zstd:1"
                        "noatime"
                        "nodiratime"
                        "ssd"
                        "space_cache=v2"
                        "discard=async"
                        "thread_pool=8"
                      ];
                    };
                  };
                };
              };
            };
          };
        };
      };
    };

    # Filesystem configuration
    fileSystems = {
      # Ensure /tmp is properly configured
      "/tmp" = {
        options = [
          "compress=zstd:1"
          "noatime"
          "nodiratime"
          "ssd"
          "space_cache=v2"
          "discard=async"
          "thread_pool=8"
        ];
      };

      # Optimize Docker directory if it exists
      "/var/lib/docker" = {
        options = [
          "compress=zstd:1"
          "noatime"
          "nodiratime"
          "ssd"
          "space_cache=v2"
          "discard=async"
          "thread_pool=8"
        ];
      };
    };

    # BTRFS-specific services and optimizations
    boot.supportedFilesystems = ["btrfs"];

    # Enable additional BTRFS kernel modules
    boot.kernelModules = ["btrfs"];

    # BTRFS kernel parameters for performance
    boot.kernelParams = [
      # BTRFS optimizations
      "rootflags=compress=zstd:3,noatime,ssd,space_cache=v2,discard=async,autodefrag,thread_pool=8"
    ];

    # Services for BTRFS maintenance
    services.btrfs.autoScrub = {
      enable = true;
      interval = "monthly";
      fileSystems = ["/"];
    };

    # Environment variables for BTRFS tools
    environment.variables = {
      BTRFS_FORGET_SCAN = "1"; # Disable slow device scanning
    };

    # Additional BTRFS optimizations via sysctl
    boot.kernel.sysctl = {
      # Optimize for BTRFS with SSDs
      "vm.dirty_background_ratio" = 5;
      "vm.dirty_ratio" = 10;
      "vm.dirty_expire_centisecs" = 6000;
      "vm.dirty_writeback_centisecs" = 100;
    };
  };
}
