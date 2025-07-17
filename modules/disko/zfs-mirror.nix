{
  config,
  lib,
  pkgs,
  ...
}: let
  # Import disk detection utilities
  diskLib = import ../../lib/disk-detection.nix {inherit lib pkgs;};

  # Auto-detect matching disks for mirror at evaluation time
  mirrorDisks = config.disko.mirrorDisks or diskLib.detectMatchingDisks {
    count = 2;
    sizeTolerancePercent = 5;
    minSizeGB = 100;
    preferSameBrand = true;
  };

  # Generate stable hostId from hostname for ZFS
  hostId = diskLib.generateHostId config.networking.hostName;
in {
  options.disko = {
    mirrorDisks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = mirrorDisks;
      description = "List of disks to use for ZFS mirror (auto-detected if not specified)";
    };
  };

  config = {
    # Validate that we have exactly 2 disks for mirror
    assertions = [
      {
        assertion = builtins.length config.disko.mirrorDisks == 2;
        message = "ZFS mirror requires exactly 2 disks, found: ${toString (builtins.length config.disko.mirrorDisks)}";
      }
    ];

    # Set the hostId based on hostname for ZFS
    networking.hostId = hostId;

    # Set filesystem type for system modules
    system.boot.filesystem = "zfs";

    boot.supportedFilesystems = ["zfs"];
    boot.zfs.forceImportRoot = false;

    # Enable ZFS services with mirror-specific settings
    services.zfs = {
      trim.enable = true;
      autoScrub.enable = true;
      autoScrub.interval = "monthly";
      # Enable automatic replacement detection
      autoReplace.enable = true;
    };

    # ZFS kernel parameters optimized for mirror setup
    boot.kernelParams = [
      "zfs.zfs_arc_max=12884901888" # 12GB ARC max (more for mirror)
      "zfs.zfs_arc_min=4294967296" # 4GB ARC min
      "zfs.l2arc_noprefetch=0" # Enable L2ARC prefetch
      "zfs.l2arc_write_boost=67108864" # 64MB write boost
      "zfs.zfs_vdev_async_read_max_active=16" # Increase for mirror reads
      "zfs.zfs_vdev_async_write_max_active=8" # Keep writes moderate
      "zfs.zfs_vdev_sync_read_max_active=16"
      "zfs.zfs_vdev_sync_write_max_active=8"
      "zfs.zfs_vdev_max_active=1000" # Max concurrent I/Os per vdev
      "zfs.zio_slow_io_ms=300" # Increase slow I/O threshold
      "zfs.zfs_prefetch_disable=0" # Enable prefetch for mirrors
      "zfs.zfs_txg_timeout=5" # Faster transaction groups
      "zfs.zfs_vdev_mirror_non_rotating_inc=2" # Prefer SSDs in mirror
    ];

    disko.devices = {
      disk = {
        # First disk in mirror
        disk1 = {
          device = builtins.elemAt config.disko.mirrorDisks 0;
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                priority = 1;
                name = "ESP1";
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
                name = "zfs1";
                size = "100%";
                content = {
                  type = "zfs";
                  pool = "rpool";
                };
              };
            };
          };
        };
        # Second disk in mirror
        disk2 = {
          device = builtins.elemAt config.disko.mirrorDisks 1;
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              ESP2 = {
                priority = 1;
                name = "ESP2";
                size = "1G";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  # Don't mount - this is backup ESP
                };
              };
              zfs = {
                priority = 2;
                name = "zfs2";
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
          mode = "mirror"; # Mirror configuration
          rootFsOptions = {
            # Mirror-optimized options
            ashift = "12"; # 4K sectors
            autotrim = "on"; # Enable automatic TRIM

            # Performance optimizations for mirror
            atime = "off";
            compression = "zstd";
            dedup = "off"; # Usually not needed with mirrors
            xattr = "sa";
            acltype = "posixacl";
            relatime = "on";

            # Record size optimizations
            recordsize = "128k";

            # Sync behavior optimized for mirrors
            sync = "standard";
            logbias = "latency"; # Mirrors can handle low latency better

            # Checksumming
            checksum = "blake3";

            # Cache settings for mirrors
            primarycache = "all";
            secondarycache = "all";

            # Mirror-specific optimizations
            redundant_metadata = "all"; # Store metadata on all disks
          };

          # Mirror-optimized mount options
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
                redundant_metadata = "all";
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
                # Enable dedup for home with mirrors (have redundancy)
                dedup = "blake3,verify";
                redundant_metadata = "all";
              };
            };
            "nix" = {
              type = "zfs_fs";
              mountpoint = "/nix";
              options = {
                mountpoint = "legacy";
                atime = "off";
                recordsize = "128k";
                logbias = "throughput";
                compression = "zstd";
                # Aggressive dedup for Nix store with mirror protection
                dedup = "blake3,verify";
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
                redundant_metadata = "all";
              };
            };
            "var/lib" = {
              type = "zfs_fs";
              options = {
                mountpoint = "legacy";
                recordsize = "128k";
                compression = "zstd";
                atime = "off";
                redundant_metadata = "all";
              };
            };
            "var/lib/docker" = {
              type = "zfs_fs";
              options = {
                mountpoint = "legacy";
                recordsize = "64k";
                logbias = "throughput";
                compression = "zstd";
                atime = "off";
                dedup = "blake3,verify"; # Safe with mirrors
                redundant_metadata = "all";
              };
            };
            "var/log" = {
              type = "zfs_fs";
              options = {
                mountpoint = "legacy";
                recordsize = "64k";
                logbias = "latency";
                compression = "gzip"; # Higher compression for logs
                atime = "off";
                redundant_metadata = "all";
              };
            };
            "tmp" = {
              type = "zfs_fs";
              mountpoint = "/tmp";
              options = {
                mountpoint = "legacy";
                recordsize = "64k";
                logbias = "latency";
                compression = "lz4";
                atime = "off";
                sync = "disabled";
                redundant_metadata = "most"; # Less critical for tmp
              };
            };
            # Separate dataset for backups/snapshots
            "backup" = {
              type = "zfs_fs";
              mountpoint = "/backup";
              options = {
                mountpoint = "legacy";
                recordsize = "1M"; # Large records for backup efficiency
                logbias = "throughput";
                compression = "gzip-9"; # Maximum compression for backups
                atime = "off";
                dedup = "sha256,verify"; # Strong dedup for backups
                redundant_metadata = "all";
              };
            };
          };
        };
      };
    };

    # Boot configuration for mirrored ESP
    boot.loader.efi.efiSysMountPoint = "/boot";

    # Sync ESP partitions script
    environment.systemPackages = with pkgs; [
      zfs
      zfs-prune-snapshots
      (writeShellScriptBin "sync-esp" ''
        #!/usr/bin/env bash
        set -euo pipefail

        echo "Syncing ESP partitions..."

        ESP1="/dev/disk/by-partlabel/ESP1"
        ESP2="/dev/disk/by-partlabel/ESP2"

        if [[ ! -b "$ESP1" ]] || [[ ! -b "$ESP2" ]]; then
          echo "ERROR: ESP partitions not found"
          exit 1
        fi

        # Mount backup ESP temporarily
        TEMP_MOUNT=$(mktemp -d)
        mount "$ESP2" "$TEMP_MOUNT"

        # Sync from primary to backup
        rsync -av --delete /boot/ "$TEMP_MOUNT/"

        # Unmount backup ESP
        umount "$TEMP_MOUNT"
        rmdir "$TEMP_MOUNT"

        echo "ESP partitions synced successfully"
      '')
      (writeShellScriptBin "zfs-mirror-health" ''
        #!/usr/bin/env bash
        echo "=== ZFS Mirror Status ==="
        zpool status -v
        echo ""
        echo "=== Mirror Resilver Progress ==="
        zpool status | grep -A5 "resilver\|scrub" || echo "No active resilver/scrub"
        echo ""
        echo "=== Disk Health ==="
        for disk in ${lib.escapeShellArgs config.disko.mirrorDisks}; do
          echo "Disk: $disk"
          smartctl -H "$disk" 2>/dev/null || echo "  SMART not available"
        done
        echo ""
        echo "=== ZFS Performance ==="
        zpool iostat -v 1 2
      '')
    ];

    # Automatic ESP sync service
    systemd.services."sync-esp" = {
      description = "Sync ESP partitions";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.rsync}/bin/rsync -av --delete /boot/ /mnt/esp2/";
        ExecStartPre = [
          "${pkgs.coreutils}/bin/mkdir -p /mnt/esp2"
          "${pkgs.util-linux}/bin/mount /dev/disk/by-partlabel/ESP2 /mnt/esp2"
        ];
        ExecStartPost = "${pkgs.util-linux}/bin/umount /mnt/esp2";
      };
    };

    systemd.timers."sync-esp" = {
      description = "Sync ESP partitions timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
      };
    };

    # Enhanced mirror monitoring
    systemd.services."zfs-mirror-monitor" = {
      description = "ZFS mirror health monitoring";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "zfs-mirror-monitor" ''
          set -euo pipefail

          # Check pool health
          if zpool status | grep -q "DEGRADED\|FAULTED\|OFFLINE\|UNAVAIL"; then
            echo "CRITICAL: ZFS mirror degraded!" >&2
            zpool status
            # Send alert if notification system is configured
            exit 1
          fi

          # Check if resilver is running
          if zpool status | grep -q "resilver in progress"; then
            echo "INFO: Mirror resilver in progress"
            zpool status | grep -A5 "resilver"
          fi

          # Check individual disk health
          for disk in ${lib.escapeShellArgs config.disko.mirrorDisks}; do
            if ! smartctl -H "$disk" >/dev/null 2>&1; then
              echo "WARNING: SMART health check failed for $disk" >&2
            fi
          done

          # Check for excessive checksum errors
          errors=$(zpool status | grep -c "cksum" | grep -v "0$" || echo "0")
          if [[ $errors -gt 0 ]]; then
            echo "WARNING: ZFS checksum errors detected on mirror!" >&2
            zpool status -v
          fi
        '';
      };
    };

    systemd.timers."zfs-mirror-monitor" = {
      description = "ZFS mirror monitoring timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*:0/30"; # Every 30 minutes
        Persistent = true;
      };
    };

    # Automatic snapshot management with mirror considerations
    services.sanoid = {
      enable = true;
      datasets = {
        "rpool/root" = {
          useTemplate = ["mirror_production"];
          recursive = true;
        };
        "rpool/home" = {
          useTemplate = ["mirror_production"];
          recursive = true;
        };
        "rpool/backup" = {
          useTemplate = ["backup"];
        };
      };
      templates = {
        mirror_production = {
          frequently = 12; # More frequent snapshots with mirror protection
          hourly = 48; # 48 hourly snapshots
          daily = 14; # 14 daily snapshots
          weekly = 8; # 8 weekly snapshots
          monthly = 24; # 24 monthly snapshots
          yearly = 5; # 5 yearly snapshots
          autosnap = true;
          autoprune = true;
        };
        backup = {
          frequently = 0; # No frequent snapshots for backup dataset
          hourly = 0;
          daily = 7; # 7 daily snapshots
          weekly = 4; # 4 weekly snapshots
          monthly = 12; # 12 monthly snapshots
          yearly = 10; # 10 yearly snapshots
          autosnap = true;
          autoprune = true;
        };
      };
    };

    # ZFS mirror-specific optimizations
    boot.kernel.sysctl = {
      # Memory tuning for mirrors
      "vm.dirty_background_ratio" = 2; # More aggressive for mirrors
      "vm.dirty_ratio" = 5;
      "vm.dirty_expire_centisecs" = 2000;
      "vm.dirty_writeback_centisecs" = 50;

      # ZFS-specific tuning for mirrors
      "vm.swappiness" = lib.mkDefault 1;
    };
  };
}
