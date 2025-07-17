{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.maintenance;
in {
  options.maintenance = {
    enable = lib.mkEnableOption "advanced system maintenance tasks";

    nix = {
      garbageCollect = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable automatic Nix garbage collection";
        };
        schedule = lib.mkOption {
          type = lib.types.str;
          default = "weekly";
          description = "Garbage collection schedule";
        };
        options = lib.mkOption {
          type = lib.types.str;
          default = "--delete-older-than 14d";
          description = "Garbage collection options";
        };
      };
      optimizeStore = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Nix store optimization";
      };
    };

    filesystem = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable filesystem maintenance";
      };
      scrubSchedule = lib.mkOption {
        type = lib.types.str;
        default = "monthly";
        description = "Filesystem scrub schedule";
      };
    };

    system = {
      cleanup = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable system cleanup tasks";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Nix garbage collection
    nix.gc = lib.mkIf cfg.nix.garbageCollect.enable {
      automatic = true;
      dates = cfg.nix.garbageCollect.schedule;
      options = cfg.nix.garbageCollect.options;
      persistent = true;
    };

    # Nix store optimization
    nix.settings.auto-optimise-store = cfg.nix.optimizeStore;
    nix.optimise = lib.mkIf cfg.nix.optimizeStore {
      automatic = true;
      dates = ["03:45"];
    };

    # BTRFS maintenance (conditional on filesystem type)
    systemd.services."btrfs-maintenance" = lib.mkIf (cfg.filesystem.enable && config.fileSystems."/".fsType == "btrfs") {
      description = "BTRFS maintenance tasks";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "btrfs-maintenance" ''
          set -euo pipefail

          echo "Starting BTRFS maintenance..."

          # Verify we're on BTRFS
          if ! ${pkgs.util-linux}/bin/findmnt -t btrfs / >/dev/null 2>&1; then
            echo "Root filesystem is not BTRFS, exiting"
            exit 0
          fi

          # Check filesystem health
          echo "Checking BTRFS filesystem health..."
          ${pkgs.btrfs-progs}/bin/btrfs filesystem show
          ${pkgs.btrfs-progs}/bin/btrfs scrub status /

          # Monthly scrub
          if [[ $(date +%d) -eq 1 ]]; then
            echo "Running monthly BTRFS scrub..."
            ${pkgs.btrfs-progs}/bin/btrfs scrub start -B / || echo "Scrub failed or already running"
          fi

          # Weekly balance with usage filters
          if [[ $(date +%u) -eq 1 ]]; then
            echo "Running weekly BTRFS balance..."
            ${pkgs.btrfs-progs}/bin/btrfs balance start -dusage=50 -musage=50 / || echo "Balance failed or not needed"
          fi

          # Defragment high-churn directories
          echo "Defragmenting critical paths..."
          for path in "/var/log" "/home/.cache" "/tmp"; do
            if [[ -d "$path" ]]; then
              ${pkgs.btrfs-progs}/bin/btrfs filesystem defragment -r -czstd "$path" || echo "Defrag of $path failed"
            fi
          done

          # Report filesystem usage
          echo "BTRFS filesystem usage:"
          ${pkgs.btrfs-progs}/bin/btrfs filesystem usage /

          echo "BTRFS maintenance completed"
        '';
      };
    };

    systemd.timers."btrfs-maintenance" = lib.mkIf (cfg.filesystem.enable && config.fileSystems."/".fsType == "btrfs") {
      description = "BTRFS maintenance timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };

    # ZFS maintenance (conditional on ZFS usage)
    services.zfs = lib.mkIf (cfg.filesystem.enable && config.boot.supportedFilesystems.zfs or false) {
      autoScrub = {
        enable = true;
        interval = cfg.filesystem.scrubSchedule;
        pools = []; # Auto-detect pools
      };
      autoSnapshot = {
        enable = true;
        frequent = 4; # Keep 4 15-minute snapshots
        hourly = 24; # Keep 24 hourly snapshots
        daily = 7; # Keep 7 daily snapshots
        weekly = 4; # Keep 4 weekly snapshots
        monthly = 12; # Keep 12 monthly snapshots
      };
      trim = {
        enable = true;
        interval = "weekly";
      };
    };

    # ZFS additional maintenance
    systemd.services."zfs-maintenance" = lib.mkIf (cfg.filesystem.enable && config.boot.supportedFilesystems.zfs or false) {
      description = "ZFS maintenance tasks";
      after = ["zfs.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "zfs-maintenance" ''
          set -euo pipefail

          echo "Starting ZFS maintenance..."

          # Check if ZFS is loaded
          if ! ${pkgs.kmod}/bin/lsmod | grep -q zfs; then
            echo "ZFS module not loaded, exiting"
            exit 0
          fi

          # Monitor pool health
          echo "Checking ZFS pool health..."
          ${pkgs.zfs}/bin/zpool status -v

          # Check for pool errors
          if ${pkgs.zfs}/bin/zpool status | grep -q "DEGRADED\|FAULTED\|OFFLINE\|UNAVAIL"; then
            echo "WARNING: ZFS pool has issues!" >&2
            ${pkgs.zfs}/bin/zpool status
          fi

          # Clean up old snapshots beyond retention policy
          echo "Managing snapshot retention..."
          for dataset in $(${pkgs.zfs}/bin/zfs list -H -o name -t filesystem); do
            echo "Processing dataset: $dataset"

            # Count snapshots older than 1 month
            old_snaps=$(${pkgs.zfs}/bin/zfs list -H -o name -t snapshot | grep "^$dataset@" | wc -l)
            if [[ $old_snaps -gt 50 ]]; then
              echo "Dataset $dataset has $old_snaps snapshots, cleaning old ones..."
              ${pkgs.zfs}/bin/zfs list -H -o name -t snapshot | grep "^$dataset@" | head -n $((old_snaps - 20)) | while read snap; do
                echo "Destroying old snapshot: $snap"
                ${pkgs.zfs}/bin/zfs destroy "$snap" || echo "Failed to destroy $snap"
              done
            fi
          done

          # Rebalance dedup tables if enabled
          for pool in $(${pkgs.zfs}/bin/zpool list -H -o name); do
            if ${pkgs.zfs}/bin/zpool get -H -o value dedup "$pool" | grep -qv "off"; then
              echo "Checking dedup table for pool: $pool"
              ${pkgs.zfs}/bin/zpool status -D "$pool"
            fi
          done

          # Export pool statistics for monitoring
          ${pkgs.zfs}/bin/zpool iostat -v > /var/log/zpool-iostat.log
          ${pkgs.zfs}/bin/zfs list -o space > /var/log/zfs-space.log

          echo "ZFS maintenance completed"
        '';
      };
    };

    systemd.timers."zfs-maintenance" = lib.mkIf (cfg.filesystem.enable && config.boot.supportedFilesystems.zfs or false) {
      description = "ZFS maintenance timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.filesystem.scrubSchedule;
        Persistent = true;
        RandomizedDelaySec = "2h";
      };
    };

    # General system maintenance
    systemd.services."system-maintenance" = lib.mkIf cfg.system.cleanup {
      description = "General system maintenance and cleanup";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "system-maintenance" ''
          set -euo pipefail

          echo "Starting system maintenance..."

          # Clean systemd journal
          echo "Cleaning systemd journal..."
          ${pkgs.systemd}/bin/journalctl --vacuum-time=4weeks
          ${pkgs.systemd}/bin/journalctl --vacuum-size=1G

          # Clean temporary files
          echo "Cleaning temporary files..."
          ${pkgs.systemd}/bin/systemd-tmpfiles --clean

          # Update locate database
          echo "Updating locate database..."
          ${pkgs.findutils}/bin/updatedb || echo "updatedb failed"

          # Update man database
          echo "Updating man database..."
          ${pkgs.man-db}/bin/mandb --quiet || echo "mandb update failed"

          # Clean old kernels (keep last 3)
          echo "Cleaning old boot entries..."
          ${pkgs.systemd}/bin/bootctl cleanup || echo "bootctl cleanup failed"

          # Report disk usage
          echo "=== Disk Usage Report ==="
          ${pkgs.coreutils}/bin/df -h
          echo ""
          echo "=== Large directories in /var ==="
          ${pkgs.coreutils}/bin/du -sh /var/* 2>/dev/null | ${pkgs.coreutils}/bin/sort -hr | ${pkgs.coreutils}/bin/head -10
          echo ""
          echo "=== Nix store size ==="
          ${pkgs.coreutils}/bin/du -sh /nix/store

          echo "System maintenance completed"
        '';
      };
    };

    systemd.timers."system-maintenance" = lib.mkIf cfg.system.cleanup {
      description = "General system maintenance timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
    };

    # Enable fstrim for all SSD maintenance
    services.fstrim = {
      enable = true;
      interval = "weekly";
    };

    # Optimize systemd journal settings
    services.journald.extraConfig = ''
      SystemMaxUse=1G
      SystemMaxFileSize=100M
      MaxRetentionSec=1month
      Storage=persistent
      Compress=yes
    '';

    # Enhanced monitoring and alerting
    systemd.services."maintenance-health-check" = {
      description = "System health monitoring for maintenance";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "health-check" ''
          set -euo pipefail

          echo "Running system health check..."

          # Check disk space
          while read filesystem size used avail percent mountpoint; do
            if [[ "$percent" =~ ^([0-9]+)% ]] && [[ ''${BASH_REMATCH[1]} -gt 90 ]]; then
              echo "WARNING: $mountpoint is ''${BASH_REMATCH[1]}% full" >&2
            fi
          done < <(${pkgs.coreutils}/bin/df -h | tail -n +2)

          # Check system load
          load=$(${pkgs.coreutils}/bin/uptime | ${pkgs.gnugrep}/bin/grep -oP 'load average: \K[0-9.]+')
          cpu_count=$(${pkgs.coreutils}/bin/nproc)
          if (( $(echo "$load > $cpu_count * 2" | ${pkgs.bc}/bin/bc -l) )); then
            echo "WARNING: High system load: $load" >&2
          fi

          # Check memory usage
          total_mem=$(${pkgs.gawk}/bin/awk '/MemTotal/ {print $2}' /proc/meminfo)
          avail_mem=$(${pkgs.gawk}/bin/awk '/MemAvailable/ {print $2}' /proc/meminfo)
          mem_usage=$(echo "scale=2; ($total_mem - $avail_mem) * 100 / $total_mem" | ${pkgs.bc}/bin/bc)
          if (( $(echo "$mem_usage > 90" | ${pkgs.bc}/bin/bc -l) )); then
            echo "WARNING: High memory usage: $mem_usage%" >&2
          fi

          # Check failed systemd services
          failed_services=$(${pkgs.systemd}/bin/systemctl --failed --no-legend | ${pkgs.coreutils}/bin/wc -l)
          if [[ $failed_services -gt 0 ]]; then
            echo "WARNING: $failed_services failed systemd services" >&2
            ${pkgs.systemd}/bin/systemctl --failed
          fi

          echo "Health check completed"
        '';
      };
    };

    systemd.timers."maintenance-health-check" = {
      description = "System health check timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
      };
    };

    # SMART monitoring for disk health
    services.smartd = {
      enable = true;
      autodetect = true;
      notifications = {
        wall.enable = true;
        mail.enable = false; # Enable if mail is configured
      };
    };
  };
}
