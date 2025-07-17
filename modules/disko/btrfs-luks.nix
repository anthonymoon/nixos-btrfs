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

    encryption = {
      tpmSupport = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable TPM2 auto-unlock support";
      };
    };
  };

  config = {
    # Set filesystem type for system modules
    system.boot.filesystem = "btrfs";
    system.boot.enableTPM = config.disko.encryption.tpmSupport;

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
              luks = {
                priority = 2;
                name = "cryptroot";
                size = "100%";
                content = {
                  type = "luks";
                  name = "root";
                  # LUKS2 with modern encryption
                  settings = {
                    allowDiscards = true;
                    bypassWorkqueues = true;
                    # TPM2 support will be configured post-install
                    crypttabExtraOpts = lib.mkIf config.disko.encryption.tpmSupport [
                      "tpm2-device=auto"
                      "tpm2-measure-pcr=no"
                      "discard"
                    ];
                  };
                  # Advanced LUKS2 parameters for performance
                  additionalKeyFiles = [];
                  content = {
                    type = "btrfs";
                    extraArgs = ["-f"];
                    # BTRFS optimizations for encrypted SSDs/NVMe
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

                      # Nix store subvolume - higher compression
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

                      # Temporary files - lighter compression
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

                      # Docker/containers subvolume
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
    };

    # LUKS configuration
    boot.initrd.luks.devices."root" = {
      device = lib.mkDefault "/dev/disk/by-partlabel/cryptroot";
      allowDiscards = true;
      bypassWorkqueues = true;
      # TPM2 configuration will be set up post-install
    };

    # Enable TPM2 support if requested
    security.tpm2 = lib.mkIf config.disko.encryption.tpmSupport {
      enable = true;
      pkcs11.enable = true;
      tctiEnvironment.enable = true;
    };

    # Systemd-cryptenroll for TPM2 (post-installation setup)
    systemd.packages = lib.mkIf config.disko.encryption.tpmSupport [pkgs.systemd];

    # Post-installation TPM2 enrollment script
    environment.systemPackages = lib.mkIf config.disko.encryption.tpmSupport [
      pkgs.tpm2-tools
      (pkgs.writeShellScriptBin "setup-tpm2-luks" ''
        #!/usr/bin/env bash
        set -euo pipefail

        echo "Setting up TPM2 auto-unlock for LUKS..."

        # Check if TPM2 is available
        if ! systemd-cryptenroll --tpm2-device=list; then
          echo "ERROR: No TPM2 device found"
          exit 1
        fi

        # Enroll TPM2 for the root device
        LUKS_DEVICE="/dev/disk/by-partlabel/cryptroot"

        if [[ ! -b "$LUKS_DEVICE" ]]; then
          echo "ERROR: LUKS device $LUKS_DEVICE not found"
          exit 1
        fi

        echo "Enrolling TPM2 for device: $LUKS_DEVICE"

        # Enroll TPM2 with current user's password
        echo "You will be prompted for your LUKS password..."
        systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7 "$LUKS_DEVICE"

        echo "TPM2 enrollment completed successfully!"
        echo "Your system should now auto-unlock on boot."
        echo "Keep your LUKS password safe as a backup!"
      '')
    ];

    # Filesystem configuration
    fileSystems = {
      # Ensure proper mount options for encrypted volumes
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
    };

    # BTRFS-specific services and optimizations
    boot.supportedFilesystems = ["btrfs"];

    # Enable additional BTRFS and crypto kernel modules
    boot.kernelModules = ["btrfs"];
    boot.initrd.kernelModules = [
      "btrfs"
      "dm_crypt"
      "aes_x86_64"
      "aesni_intel"
      "cryptd"
    ];

    # BTRFS kernel parameters for encrypted performance
    boot.kernelParams = [
      # BTRFS optimizations
      "rootflags=compress=zstd:3,noatime,ssd,space_cache=v2,discard=async,autodefrag,thread_pool=8"

      # Crypto performance optimizations
      "cryptomgr.notests" # Skip crypto self-tests for faster boot
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

    # Performance optimizations for encrypted storage
    boot.kernel.sysctl = {
      # Optimize for BTRFS with SSDs and encryption
      "vm.dirty_background_ratio" = 5;
      "vm.dirty_ratio" = 10;
      "vm.dirty_expire_centisecs" = 6000;
      "vm.dirty_writeback_centisecs" = 100;

      # Crypto performance
      "vm.swappiness" = 1; # Reduce swap usage to avoid encryption overhead
    };
  };
}
