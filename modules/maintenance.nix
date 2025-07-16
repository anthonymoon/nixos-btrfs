{
  config,
  lib,
  pkgs,
  ...
}: {
  systemd.services = {
    btrfs-scrub = {
      description = "Monthly Btrfs scrub";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.btrfs-progs}/bin/btrfs scrub start -B /";
      };
    };

    btrfs-balance = {
      description = "Weekly Btrfs balance";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.btrfs-progs}/bin/btrfs balance start -dusage=50 -musage=50 /";
        IOSchedulingClass = "idle";
        CPUSchedulingPolicy = "idle";
      };
    };

    btrfs-trim = {
      description = "Weekly Btrfs trim";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.util-linux}/bin/fstrim -av";
      };
    };

    system-backup = {
      description = "System configuration backup";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "backup-config" ''
          #!/usr/bin/env bash
          BACKUP_DIR="/var/backups/nixos-config"
          DATE=$(date +%Y%m%d-%H%M%S)

          mkdir -p "$BACKUP_DIR"
          cd /etc/nixos || exit 1

          # Backup flake and lock
          cp flake.{nix,lock} "$BACKUP_DIR/" 2>/dev/null || true

          # Create tarball of current config
          tar czf "$BACKUP_DIR/config-$DATE.tar.gz" .

          # Keep only last 10 backups
          ls -t "$BACKUP_DIR"/config-*.tar.gz | tail -n +11 | xargs -r rm
        '';
      };
    };

    system-health-check = {
      description = "System health monitoring";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "health-check" ''
          #!/usr/bin/env bash
          echo "=== System Health Check ==="

          # Disk usage
          echo "Disk Usage:"
          df -h / /home /nix

          # Btrfs status
          echo -e "\nBtrfs Status:"
          btrfs filesystem show /
          btrfs device stats /

          # Failed services
          echo -e "\nFailed Services:"
          systemctl --failed --no-pager

          # Memory usage
          echo -e "\nMemory Usage:"
          free -h

          # Journal errors
          echo -e "\nRecent Errors (last 24h):"
          journalctl -p err -S "24 hours ago" --no-pager | tail -20
        '';
      };
    };
  };

  systemd.timers = {
    btrfs-scrub = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "monthly";
        Persistent = true;
      };
    };

    btrfs-balance = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
      };
    };

    btrfs-trim = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "weekly";
        RandomizedDelaySec = "6h";
        Persistent = true;
      };
    };

    system-backup = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };

    system-health-check = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "daily";
        OnBootSec = "10min";
        Persistent = true;
      };
    };
  };

  # Enable Btrfs auto-defrag
  fileSystems =
    lib.mapAttrs (
      name: fs:
        fs
        // lib.optionalAttrs (fs.fsType == "btrfs") {
          options = fs.options ++ ["autodefrag"];
        }
    )
    config.fileSystems;

  # Nix store optimization
  nix.optimise = {
    automatic = true;
    dates = ["weekly"];
  };

  # Smart monitoring
  services.smartd = {
    enable = true;
    autodetect = true;
    notifications = {
      wall.enable = true;
      mail = {
        enable = false; # Enable if mail is configured
      };
    };
  };
}
