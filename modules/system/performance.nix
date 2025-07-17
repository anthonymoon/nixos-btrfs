{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.system.performance;
in {
  options.system.performance = {
    enable = lib.mkEnableOption "system performance optimizations";

    zramSwap = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable ZRAM compressed swap";
      };
      memoryPercent = lib.mkOption {
        type = lib.types.int;
        default = 50;
        description = "Percentage of RAM to use for ZRAM";
      };
      memoryMax = lib.mkOption {
        type = lib.types.int;
        default = 16 * 1024 * 1024 * 1024; # 16GB
        description = "Maximum ZRAM size in bytes";
      };
    };

    nvmeOptimizations = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable NVMe-specific optimizations";
    };

    disableMitigations = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Disable CPU vulnerability mitigations for performance (security risk)";
    };
  };

  config = lib.mkIf cfg.enable {
    # ZRAM swap configuration
    zramSwap = lib.mkIf cfg.zramSwap.enable {
      enable = true;
      algorithm = "zstd";
      memoryPercent = cfg.zramSwap.memoryPercent;
      memoryMax = cfg.zramSwap.memoryMax;
      priority = 5; # Higher priority than disk swap
    };

    # Kernel parameters for better performance
    boot.kernel.sysctl = {
      # VM tuning for better responsiveness
      # vm.swappiness is set in virtualization.nix or disk configs
      "vm.vfs_cache_pressure" = lib.mkDefault 50; # Keep file cache longer
      "vm.dirty_ratio" = lib.mkDefault 10; # Start writeback at 10% dirty pages
      "vm.dirty_background_ratio" = lib.mkDefault 5; # Background writeback at 5%
      "vm.dirty_expire_centisecs" = lib.mkDefault 6000; # Dirty data expires after 60 seconds
      "vm.dirty_writeback_centisecs" = lib.mkDefault 100; # Check for dirty data every second

      # Network performance optimizations
      "net.core.default_qdisc" = lib.mkDefault "cake"; # Better queueing discipline
      "net.ipv4.tcp_congestion" = lib.mkDefault "bbr"; # Better congestion control
      "net.core.netdev_max_backlog" = lib.mkDefault 5000;
      "net.core.rmem_default" = lib.mkDefault 262144;
      "net.core.rmem_max" = lib.mkDefault 67108864;
      "net.core.wmem_default" = lib.mkDefault 262144;
      "net.core.wmem_max" = lib.mkDefault 67108864;

      # File system performance
      "fs.file-max" = lib.mkDefault 2097152; # Maximum number of open files

      # General responsiveness
      "kernel.sched_autogroup_enabled" = lib.mkDefault 1; # Better desktop responsiveness
      "kernel.sched_migration_cost_ns" = lib.mkDefault 5000000; # Reduce CPU migration
    };

    # NVMe-specific kernel parameters
    boot.kernelParams = lib.mkMerge [
      # Always include basic optimizations
      [
        # I/O scheduler - let kernel decide based on device type
        "elevator=none" # Will be overridden by udev rules per device type

        # Memory optimizations
        "transparent_hugepage=madvise" # Use huge pages when requested

        # General performance
        "nowatchdog" # Disable hardware watchdog (optional)
      ]

      # NVMe specific optimizations
      (lib.mkIf cfg.nvmeOptimizations [
        "nvme_core.default_ps_max_latency_us=0" # Disable NVMe power saving
        "nvme_core.io_timeout=4294967295" # Maximum I/O timeout for stability
        "nvme.poll_queues=8" # Enable polling queues for lower latency
      ])

      # CPU mitigations (optional, security vs performance trade-off)
      (lib.mkIf cfg.disableMitigations [
        "mitigations=off" # Disable all CPU vulnerability mitigations
        "spectre_v2=off"
        "spec_store_bypass_disable=off"
        "l1tf=off"
        "mds=off"
        "tsx_async_abort=off"
      ])
    ];

    # I/O scheduler optimization based on device type
    services.udev.extraRules = ''
      # NVMe devices: use none scheduler (no queuing needed)
      ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
      ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/nr_requests}="2048"
      ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/rq_affinity}="2"
      ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/nomerges}="2"
      ${lib.optionalString cfg.nvmeOptimizations ''
        ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/io_poll}="1"
        ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/io_poll_delay}="-1"
      ''}

      # SATA SSD: use mq-deadline for better latency
      ACTION=="add|change", KERNEL=="sd[a-z]|hd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
      ACTION=="add|change", KERNEL=="sd[a-z]|hd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/nr_requests}="256"
      ACTION=="add|change", KERNEL=="sd[a-z]|hd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/read_ahead_kb}="128"

      # Traditional HDD: use bfq for better fairness and responsiveness
      ACTION=="add|change", KERNEL=="sd[a-z]|hd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
      ACTION=="add|change", KERNEL=="sd[a-z]|hd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/nr_requests}="64"
      ACTION=="add|change", KERNEL=="sd[a-z]|hd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/read_ahead_kb}="512"

      # General optimizations for all block devices
      ACTION=="add|change", KERNEL=="sd[a-z]|hd[a-z]|nvme[0-9]n[0-9]", ATTR{queue/add_random}="0"
      ACTION=="add|change", KERNEL=="sd[a-z]|hd[a-z]|nvme[0-9]n[0-9]", ATTR{queue/discard_max_bytes}="2147483648"
    '';

    # CPU governor for better performance
    powerManagement.cpuFreqGovernor = lib.mkDefault "performance";

    # Optimize CPU performance
    powerManagement.powertop.enable = false; # Conflicts with performance settings

    # Thermal management
    services.thermald.enable = lib.mkDefault true;

    # Enable fstrim for SSD maintenance
    services.fstrim = {
      enable = true;
      interval = "weekly";
    };

    # Optimize systemd for performance
    systemd.extraConfig = ''
      DefaultTimeoutStopSec=10s
      DefaultTimeoutStartSec=10s
    '';

    # User limits for performance
    security.pam.loginLimits = [
      # Increase file descriptor limits
      {
        domain = "*";
        type = "soft";
        item = "nofile";
        value = "65536";
      }
      {
        domain = "*";
        type = "hard";
        item = "nofile";
        value = "1048576";
      }

      # Increase process limits
      {
        domain = "*";
        type = "soft";
        item = "nproc";
        value = "32768";
      }
      {
        domain = "*";
        type = "hard";
        item = "nproc";
        value = "65536";
      }

      # Memory lock limits (useful for real-time applications)
      {
        domain = "*";
        type = "soft";
        item = "memlock";
        value = "unlimited";
      }
      {
        domain = "*";
        type = "hard";
        item = "memlock";
        value = "unlimited";
      }
    ];

    # Optimize journal for performance
    services.journald.extraConfig = ''
      SystemMaxUse=1G
      SystemMaxFileSize=100M
      MaxRetentionSec=1month
      ForwardToSyslog=no
      Storage=persistent
      Compress=yes
    '';

    # Network optimizations
    boot.kernelModules = ["tcp_bbr"];

    # Additional system optimizations
    systemd.services."optimize-system" = {
      description = "Apply runtime system optimizations";
      wantedBy = ["multi-user.target"];
      after = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "optimize-system" ''
          set -euo pipefail

          # Optimize CPU scaling
          for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            [[ -f "$cpu" ]] && echo "performance" > "$cpu" 2>/dev/null || true
          done

          # Disable CPU frequency scaling for consistent performance
          for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do
            if [[ -f "$cpu" ]]; then
              max_freq=$(cat "$cpu")
              echo "$max_freq" > "''${cpu/max/min}" 2>/dev/null || true
            fi
          done

          # Set CPU energy policy to performance (Intel)
          for policy in /sys/devices/system/cpu/cpu*/power/energy_perf_bias; do
            [[ -f "$policy" ]] && echo "0" > "$policy" 2>/dev/null || true
          done

          # Disable ASLR for slightly better performance (security trade-off)
          ${lib.optionalString cfg.disableMitigations ''
            echo 0 > /proc/sys/kernel/randomize_va_space 2>/dev/null || true
          ''}

          # Optimize network buffer sizes dynamically
          total_mem=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
          if [[ $total_mem -gt 8388608 ]]; then  # > 8GB RAM
            echo 16777216 > /proc/sys/net/core/rmem_max 2>/dev/null || true
            echo 16777216 > /proc/sys/net/core/wmem_max 2>/dev/null || true
          fi

          echo "System optimizations applied successfully"
        '';
      };
    };
  };
}
