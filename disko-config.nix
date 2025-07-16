# Disko configuration for ZFS with deduplication
{lib, ...}: {
  disko.devices = {
    disk.main = {
      device = lib.mkDefault "/dev/sda";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            name = "boot";
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = ["defaults" "umask=0077"];
            };
          };
          root = {
            name = "root";
            size = "100%";
            content = {
              type = "zfs";
              pool = "zroot";
            };
          };
        };
      };
    };

    zpool.zroot = {
      type = "zpool";
      mode = "single";
      options = {
        ashift = "12";
        autotrim = "on";
      };
      rootFsOptions = {
        compression = "lz4";
        acltype = "posixacl";
        dnodesize = "auto";
        normalization = "formD";
        relatime = "on";
        xattr = "sa";
        mountpoint = "none";
        canmount = "off";
        encryption = "off";
      };

      datasets = {
        # Root filesystem
        "root" = {
          type = "zfs_fs";
          mountpoint = "/";
          options = {
            compression = "lz4";
            canmount = "on";
          };
        };

        # Home directory
        "home" = {
          type = "zfs_fs";
          mountpoint = "/home";
          options = {
            compression = "zstd-3";
            recordsize = "1M";
            canmount = "on";
          };
        };

        # Nix store with deduplication
        "nix" = {
          type = "zfs_fs";
          mountpoint = "/nix";
          options = {
            compression = "zstd-6";
            recordsize = "64K";
            dedup = "on";
            atime = "off";
            canmount = "on";
          };
        };

        # Persistent data
        "persist" = {
          type = "zfs_fs";
          mountpoint = "/persist";
          options = {
            compression = "lz4";
            canmount = "on";
          };
        };

        # Variable data
        "var" = {
          type = "zfs_fs";
          mountpoint = "/var";
          options = {
            compression = "lz4";
            canmount = "on";
          };
        };

        # Logs
        "var/log" = {
          type = "zfs_fs";
          mountpoint = "/var/log";
          options = {
            compression = "gzip";
            recordsize = "128K";
            canmount = "on";
          };
        };

        # Reserved space for emergencies
        "reserved" = {
          type = "zfs_fs";
          options = {
            refreservation = "10G";
            canmount = "off";
          };
        };
      };
    };
  };
}
