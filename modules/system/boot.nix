{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.system.boot;
in {
  options.system.boot = {
    enable = lib.mkEnableOption "enhanced boot configuration";

    filesystem = lib.mkOption {
      type = lib.types.enum ["btrfs" "zfs" "ext4"];
      default = "btrfs";
      description = "Primary filesystem type for optimization";
    };

    enableTPM = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable TPM support for encryption";
    };

    secureBoot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable secure boot with lanzaboote";
    };

    kernelVariant = lib.mkOption {
      type = lib.types.enum ["latest" "lts" "zen" "hardened"];
      default = "latest";
      description = "Kernel variant to use";
    };
  };

  config = lib.mkIf cfg.enable {
    # Kernel selection based on variant
    boot.kernelPackages = lib.mkDefault (
      if cfg.kernelVariant == "latest"
      then pkgs.linuxPackages_latest
      else if cfg.kernelVariant == "lts"
      then pkgs.linuxPackages_lts
      else if cfg.kernelVariant == "zen"
      then pkgs.linuxPackages_zen
      else if cfg.kernelVariant == "hardened"
      then pkgs.linuxPackages_hardened
      else pkgs.linuxPackages_latest
    );

    # Essential boot configuration
    boot = {
      # Bootloader configuration
      loader = {
        systemd-boot = lib.mkIf (!cfg.secureBoot) {
          enable = true;
          editor = false; # Disable editing boot entries for security
          configurationLimit = 20; # Keep more generations
          consoleMode = "auto";
        };

        efi = {
          canTouchEfiVariables = true;
          efiSysMountPoint = "/boot";
        };

        timeout = 3; # Quick boot timeout
      };

      # Initrd configuration optimized for different filesystems
      initrd = {
        # Core modules needed for boot
        availableKernelModules =
          [
            # Storage controllers
            "nvme"
            "xhci_pci"
            "ahci"
            "usbhid"
            "usb_storage"
            "sd_mod"
            "sr_mod"

            # Filesystem support
            "ext4"
            "vfat"
          ]
          ++ lib.optionals (cfg.filesystem == "btrfs") [
            "btrfs"
          ]
          ++ lib.optionals (cfg.filesystem == "zfs") [
            "zfs"
            "spl"
          ];

        # Kernel modules to load early
        kernelModules =
          [
            # Encryption and TPM
            "dm_mod"
            "dm_crypt"
            "aes"
            "aes_x86_64"
            "aesni_intel"
            "cryptd"
          ]
          ++ lib.optionals cfg.enableTPM [
            "tpm"
            "tpm_tis"
            "tpm_crb"
            "tpm_infineon"
          ]
          ++ lib.optionals (cfg.filesystem == "btrfs") [
            "crc32c"
            "crc32c_intel"
          ];

        # Include required tools in initrd
        extraUtilsCommands = ''
          # Essential utilities
          copy_bin_and_libs ${pkgs.util-linux}/bin/blkid
          copy_bin_and_libs ${pkgs.util-linux}/bin/mount
          copy_bin_and_libs ${pkgs.util-linux}/bin/umount
          copy_bin_and_libs ${pkgs.util-linux}/bin/lsblk

          # Filesystem-specific tools
          ${lib.optionalString (cfg.filesystem == "btrfs") ''
            copy_bin_and_libs ${pkgs.btrfs-progs}/bin/btrfs
            copy_bin_and_libs ${pkgs.btrfs-progs}/bin/btrfsck
          ''}

          ${lib.optionalString (cfg.filesystem == "zfs") ''
            copy_bin_and_libs ${pkgs.zfs}/bin/zfs
            copy_bin_and_libs ${pkgs.zfs}/bin/zpool
            copy_bin_and_libs ${pkgs.zfs}/bin/zdb
          ''}

          # TPM tools if enabled
          ${lib.optionalString cfg.enableTPM ''
            copy_bin_and_libs ${pkgs.tpm2-tools}/bin/tpm2_unseal || true
            copy_bin_and_libs ${pkgs.tpm2-tools}/bin/tpm2_load || true
          ''}
        '';

        # Early device setup and optimizations
        preLVMCommands = ''
          # Enable early loading messages
          echo "Loading essential drivers..."

          # Detect and optimize NVMe devices early
          for nvme in /sys/class/block/nvme*; do
            if [[ -d "$nvme" ]]; then
              dev=$(basename "$nvme")
              echo "Optimizing NVMe device: $dev"

              # Set queue depth early
              echo 2048 > /sys/class/block/$dev/queue/nr_requests 2>/dev/null || true
              echo 2 > /sys/class/block/$dev/queue/nomerges 2>/dev/null || true
              echo 2 > /sys/class/block/$dev/queue/rq_affinity 2>/dev/null || true

              # Enable polling if supported
              echo 1 > /sys/class/block/$dev/queue/io_poll 2>/dev/null || true
              echo -1 > /sys/class/block/$dev/queue/io_poll_delay 2>/dev/null || true
            fi
          done

          # Set optimal readahead for detected devices
          for dev in /sys/class/block/sd* /sys/class/block/nvme*; do
            if [[ -d "$dev" ]]; then
              devname=$(basename "$dev")

              # Check if it's rotational (HDD vs SSD)
              if [[ -f "$dev/queue/rotational" ]]; then
                rotational=$(cat "$dev/queue/rotational")
                if [[ "$rotational" == "0" ]]; then
                  # SSD/NVMe - smaller readahead
                  echo 256 > "$dev/queue/read_ahead_kb" 2>/dev/null || true
                else
                  # HDD - larger readahead
                  echo 1024 > "$dev/queue/read_ahead_kb" 2>/dev/null || true
                fi
              fi
            fi
          done
        '';

        # Post device commands for filesystem-specific optimizations
        postDeviceCommands = lib.mkAfter ''
          ${lib.optionalString (cfg.filesystem == "btrfs") ''
            # BTRFS-specific early optimizations
            echo "Applying BTRFS optimizations in initrd..."

            # Enable compression detection
            modprobe zstd 2>/dev/null || true
            modprobe lzo 2>/dev/null || true
          ''}

          ${lib.optionalString (cfg.filesystem == "zfs") ''
            # ZFS-specific early optimizations
            echo "Applying ZFS optimizations in initrd..."

            # Set ZFS parameters early
            echo 1 > /sys/module/zfs/parameters/zfs_prefetch_disable 2>/dev/null || true
          ''}

          # Apply final device optimizations
          echo "Finalizing device optimizations..."
          udevadm settle --timeout=10
        '';

        # Optimize initrd generation
        compressor = "zstd";
        compressorArgs = ["-19" "-T0"]; # Maximum compression with all threads

        # Include firmware for hardware support
        includeDefaultModules = true;
      };

      # Kernel parameters for different filesystems
      kernelParams =
        [
          # Basic boot optimizations
          "quiet"
          "splash"
          "loglevel=3"
          "rd.systemd.show_status=false"
          "rd.udev.log_level=3"
          "udev.log_priority=3"

          # Console configuration
          "console=tty0"
          "vt.global_cursor_default=0" # Hide cursor

          # Memory and performance
          "intel_idle.max_cstate=1" # Better performance on Intel
          "processor.max_cstate=1"

          # Security (can be disabled for performance)
          "init_on_alloc=1"
          "init_on_free=1"
          "page_alloc.shuffle=1"
        ]
        ++ lib.optionals (cfg.filesystem == "btrfs") [
          # BTRFS-specific parameters
          "rootflags=compress=zstd:3,noatime,ssd,space_cache=v2"
        ]
        ++ lib.optionals (cfg.filesystem == "zfs") [
          # ZFS-specific parameters
          "zfs.zfs_arc_max=8589934592" # 8GB ARC max
          "zfs.zfs_arc_min=2147483648" # 2GB ARC min
          "zfs.l2arc_noprefetch=0"
          "zfs.zfs_txg_timeout=5"
          "zfs.zfs_vdev_async_read_max_active=8"
          "zfs.zfs_vdev_async_write_max_active=8"
          "zfs.zfs_vdev_sync_read_max_active=8"
          "zfs.zfs_vdev_sync_write_max_active=8"
          "zfs.zfs_vdev_max_active=1000"
          "zfs.zio_slow_io_ms=300"
          "zfs.zfs_prefetch_disable=0"
        ];

      # Clean temporary files on boot
      tmp = {
        cleanOnBoot = true;
        useTmpfs = true;
        tmpfsSize = "50%"; # Use up to 50% of RAM for /tmp
      };

      # Additional kernel modules for hardware support
      kernelModules =
        [
          # Virtualization
          "kvm-amd"
          "kvm-intel"

          # Additional crypto
          "aes_x86_64"
          "sha256_ssse3"
          "crc32_pclmul"
          "crc32c_intel"
        ]
        ++ lib.optionals cfg.enableTPM [
          "tpm_rng"
        ];

      # Blacklist problematic modules
      blacklistedKernelModules = [
        # Disable watchdog for better performance
        "iTCO_wdt"
        "iTCO_vendor_support"

        # Disable problematic wifi (if using external adapters)
        # "rtw88_8822be"

        # Disable speaker
        "pcspkr"
        "snd_pcsp"
      ];

      # Enable plymouth for better boot experience
      plymouth = {
        enable = true;
        theme = "breeze";
      };

      # Filesystem support
      supportedFilesystems =
        [cfg.filesystem]
        ++ ["vfat" "ntfs" "exfat"]
        ++ lib.optionals (cfg.filesystem != "btrfs") ["btrfs"]
        ++ lib.optionals (cfg.filesystem != "zfs") ["zfs"]
        ++ lib.optionals (cfg.filesystem != "ext4") ["ext4"];
    };

    # Hardware acceleration and drivers
    hardware = {
      enableAllFirmware = true;
      enableRedistributableFirmware = true;

      # CPU microcode
      cpu.intel.updateMicrocode = lib.mkDefault true;
      cpu.amd.updateMicrocode = lib.mkDefault true;

      # Graphics
      graphics = {
        enable = true;
        enable32Bit = true;
      };
    };

    # Early systemd optimizations
    systemd = {
      # Faster boot times
      extraConfig = ''
        DefaultTimeoutStartSec=30s
        DefaultTimeoutStopSec=15s
        DefaultDeviceTimeoutSec=10s
      '';

      # Optimize journald for boot
      services.systemd-journald.serviceConfig = {
        SystemMaxUse = "100M";
        RuntimeMaxUse = "50M";
        MaxFileSec = "1week";
      };
    };

    # TPM configuration if enabled
    security.tpm2 = lib.mkIf cfg.enableTPM {
      enable = true;
      pkcs11.enable = true; # PKCS#11 support
      tctiEnvironment.enable = true; # Enable TCTI
    };

    # Additional boot optimizations
    services = {
      # Optimize udev
      udev = {
        extraRules = ''
          # Skip network interface renaming for faster boot
          SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="", NAME="eth0"

          # Faster disk detection
          ACTION=="add", SUBSYSTEM=="block", RUN+="${pkgs.coreutils}/bin/echo noop > /sys/class/block/%k/queue/scheduler"
        '';

        # Reduce udev worker count for faster processing
        extraHwdb = ''
          # Optimize udev processing
          udev_workers_max=8
        '';
      };
    };

    # Filesystem-specific configurations
    fileSystems = lib.mkMerge [
      # Common EFI boot partition
      {
        "/boot" = {
          options = [
            "umask=0077"
            "noatime"
            "nodiratime"
          ];
        };
      }

      # BTRFS-specific mount options
      (lib.mkIf (cfg.filesystem == "btrfs") {
        "/" = {
          options = [
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
      })

      # ZFS-specific mount options
      (lib.mkIf (cfg.filesystem == "zfs") {
        "/" = {
          options = [
            "noatime"
            "nodiratime"
          ];
        };
      })
    ];
  };
}
