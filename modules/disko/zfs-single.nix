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

  # Generate stable hostId from hostname for ZFS
  hostId = diskLib.generateHostId config.networking.hostName;
in {
  options.disko = {
    primaryDisk = lib.mkOption {
      type = lib.types.str;
      default = primaryDisk;
      description = "Primary disk to use for installation (auto-detected if not specified)";
    };
  };

  config = {
    # Set the hostId based on hostname for ZFS
    networking.hostId = hostId;

    # Set filesystem type for system modules
    system.boot.filesystem = "zfs";

    boot.supportedFilesystems = ["zfs"];
    boot.zfs.forceImportRoot = false;

    # Enable ZFS services
    services.zfs = {
      trim.enable = true;
      autoScrub.enable = true;
      autoScrub.interval = "monthly";
    };

    # ZFS kernel parameters with NVMe optimizations
    boot.kernelParams = [
      "zfs.zfs_arc_max=8589934592" # 8GB ARC max
      "zfs.zfs_arc_min=2147483648" # 2GB ARC min
      "zfs.l2arc_noprefetch=0" # Enable L2ARC prefetch
      "zfs.l2arc_write_boost=33554432" # 32MB write boost
      "zfs.zfs_vdev_async_read_max_active=8" # Increase async reads for NVMe
      "zfs.zfs_vdev_async_write_max_active=8" # Increase async writes for NVMe
      "zfs.zfs_vdev_sync_read_max_active=8"
      "zfs.zfs_vdev_sync_write_max_active=8"
      "zfs.zfs_vdev_max_active=1000" # Max concurrent I/Os per vdev
      "zfs.zio_slow_io_ms=300" # Increase slow I/O threshold for NVMe
      "zfs.zfs_prefetch_disable=0" # Enable prefetch
      "zfs.zfs_txg_timeout=5" # Faster transaction groups
    ];

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
              zfs = {
                priority = 2;
                name = "zfs";
                size = "100%";
                content = {
                  type = "zfs";
                  pool = "rpool";
                };
              };
            };
          };
        };
      };
      zpool = {
        rpool = {
          type = "zpool";
          mode = ""; # Single disk
          rootFsOptions = {
            # NVMe-optimized options
            ashift = "12"; # 4K sectors (2^12 = 4096)
            autotrim = "on"; # Enable automatic TRIM

            # Performance optimizations
            atime = "off";
            compression = "zstd";
            dedup = "off"; # Disable global dedup, enable per-dataset if needed
            xattr = "sa";
            acltype = "posixacl";
            relatime = "on";

            # Record size optimizations
            recordsize = "128k"; # Default, tune per dataset

            # Sync behavior
            sync = "standard";
            logbias = "latency"; # Optimize for low latency (NVMe)

            # Checksumming
            checksum = "blake3"; # Faster than SHA256

            # Cache settings
            primarycache = "all";
            secondarycache = "all";
          };

          # NVMe-optimized mount options
          mountOptions = [
            "noatime"
            "nodiratime"
          ];

          datasets = {
            "root" = {
              type = "zfs_fs";
              mountpoint = "/";
              options = {
                mountpoint = "legacy";
                recordsize = "128k";
                logbias = "latency";
                compression = "zstd";
                atime = "off";
              };
            };
            "home" = {
              type = "zfs_fs";
              mountpoint = "/home";
              options = {
                mountpoint = "legacy";
                recordsize = "128k";
                logbias = "latency";
                compression = "zstd";
                atime = "off";
                # Optional deduplication for home (user files often have duplicates)
                # dedup = "blake3,verify";
              };
            };
            "nix" = {
              type = "zfs_fs";
              mountpoint = "/nix";
              options = {
                mountpoint = "legacy";
                atime = "off";
                recordsize = "128k";
                logbias = "throughput"; # Nix store benefits from throughput
                compression = "zstd";
                # Good candidate for deduplication (many duplicate files in Nix store)
                dedup = "blake3,verify";
                # Optimize for many small files
                redundant_metadata = "all";
              };
            };
            "var" = {
              type = "zfs_fs";
              mountpoint = "/var";
              options = {
                mountpoint = "legacy";
                recordsize = "128k";
                logbias = "latency";
                compression = "zstd";
                atime = "off";
              };
            };
            "var/lib" = {
              type = "zfs_fs";
              options = {
                mountpoint = "legacy";
                recordsize = "128k";
                compression = "zstd";
                atime = "off";
              };
            };
            "var/lib/docker" = {
              type = "zfs_fs";
              options = {
                mountpoint = "legacy";
                recordsize = "64k"; # Better for container layers
                logbias = "throughput";
                compression = "zstd";
                atime = "off";
                # Docker benefits from dedup (container image layers)
                dedup = "blake3,verify";
              };
            };
            "var/log" = {
              type = "zfs_fs";
              options = {
                mountpoint = "legacy";
                recordsize = "64k"; # Better for log files
                logbias = "latency";
                compression = "gzip"; # Higher compression for logs
                atime = "off";
              };
            };
            "tmp" = {
              type = "zfs_fs";
              mountpoint = "/tmp";
              options = {
                mountpoint = "legacy";
                recordsize = "64k";
                logbias = "latency";
                compression = "lz4"; # Fast compression for temporary files
                atime = "off";
                sync = "disabled"; # Temporary files don't need sync
              };
            };
          };
        };
      };
    };

    # Filesystem configuration
    fileSystems = {
      # Ensure proper ZFS mount options
      "/" = {
        options = [
          "noatime"
          "nodiratime"
        ];
      };
    };

    # Additional ZFS configuration
    boot.kernelModules = ["zfs"];
    boot.initrd.kernelModules = ["zfs"];

    # ZFS-specific optimizations
    boot.kernel.sysctl = {
      # ZFS memory tuning
      "vm.dirty_background_ratio" = 3;
      "vm.dirty_ratio" = 8;
      "vm.dirty_expire_centisecs" = 3000;
      "vm.dirty_writeback_centisecs" = 100;

      # ZFS-specific tuning
      "vm.swappiness" = lib.mkDefault 1; # ZFS handles memory better, reduce swap usage
    };

    # Environment variables for ZFS
    environment.variables = {
      ZFS_COLOR = "1"; # Enable colored ZFS output
    };

    # Additional ZFS tools in system packages
    environment.systemPackages = with pkgs; [
      zfs
      zfs-prune-snapshots
      (writeShellScriptBin "zfs-health" ''
        #!/usr/bin/env bash
        echo "=== ZFS Pool Status ==="
        zpool status -v
        echo ""
        echo "=== ZFS Pool I/O Stats ==="
        zpool iostat -v 1 2
        echo ""
        echo "=== ZFS Datasets ==="
        zfs list -o name,used,avail,refer,mountpoint
        echo ""
        echo "=== ZFS ARC Stats ==="
        arc_summary.py 2>/dev/null || echo "arc_summary.py not available"
      '')
    ];

    # Automatic snapshot management
    services.sanoid = {
      enable = true;
      datasets = {
        "rpool/root" = {
          useTemplate = ["production"];
          recursive = true;
        };
        "rpool/home" = {
          useTemplate = ["production"];
          recursive = true;
        };
      };
      templates.production = {
        frequently = 8; # 8 snapshots taken every 15 minutes
        hourly = 24; # 24 hourly snapshots
        daily = 7; # 7 daily snapshots
        weekly = 4; # 4 weekly snapshots
        monthly = 12; # 12 monthly snapshots
        yearly = 0; # No yearly snapshots
        autosnap = true;
        autoprune = true;
      };
    };

    # ZFS scrub service enhancement
    systemd.services."zfs-scrub@" = {
      serviceConfig = {
        IOSchedulingClass = 3; # Idle priority
        IOSchedulingPriority = 7;
        CPUSchedulingPolicy = "idle";
      };
    };

    # Monitor ZFS health
    systemd.services."zfs-health-monitor" = {
      description = "ZFS health monitoring";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "zfs-health-monitor" ''
          set -euo pipefail

          # Check pool health
          if zpool status | grep -q "DEGRADED\|FAULTED\|OFFLINE\|UNAVAIL"; then
            echo "WARNING: ZFS pool has issues!" >&2
            zpool status
            exit 1
          fi

          # Check for checksum errors
          errors=$(zpool status | grep -E "cksum|errors:" | grep -v "No known data errors" | wc -l)
          if [[ $errors -gt 0 ]]; then
            echo "WARNING: ZFS checksum errors detected!" >&2
            zpool status -v
          fi

          # Check ARC efficiency
          arc_hit_ratio=$(arc_summary.py 2>/dev/null | grep "Cache Hit Ratio" | awk '{print $4}' | tr -d '%' || echo "0")
          if [[ $arc_hit_ratio -lt 90 ]]; then
            echo "INFO: ZFS ARC hit ratio is $arc_hit_ratio% (consider tuning)" >&2
          fi
        '';
      };
    };

    systemd.timers."zfs-health-monitor" = {
      description = "ZFS health monitoring timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
      };
    };
  };
}
