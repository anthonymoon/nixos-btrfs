# Disko configuration for rpool structure
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/disk/by-id/PLACEHOLDER"; # Replace with actual disk
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["defaults"];
              };
            };
            swap = {
              size = "8G";
              content = {
                type = "swap";
                randomEncryption = true;
              };
            };
            zfs = {
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
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          acltype = "posixacl";
          canmount = "off";
          dnodesize = "auto";
          normalization = "formD";
          relatime = "on";
          xattr = "sa";
          mountpoint = "none";
          compression = "lz4";
        };
        datasets = {
          # Local datasets (can be destroyed/recreated)
          "local" = {
            type = "zfs_fs";
            options = {
              canmount = "off";
              mountpoint = "none";
            };
          };
          "local/root" = {
            type = "zfs_fs";
            mountpoint = "/";
            options = {
              canmount = "noauto";
              mountpoint = "legacy";
            };
          };
          "local/nix" = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options = {
              atime = "off";
              canmount = "on";
              mountpoint = "/nix";
            };
          };
          "local/nix-store" = {
            type = "zfs_fs";
            mountpoint = "/nix/store";
            options = {
              atime = "off";
              canmount = "on";
              mountpoint = "/nix/store";
            };
          };
          "local/cache" = {
            type = "zfs_fs";
            mountpoint = "/cache";
            options = {
              canmount = "on";
              mountpoint = "/cache";
            };
          };

          # Safe datasets (preserved across reinstalls)
          "safe" = {
            type = "zfs_fs";
            options = {
              canmount = "off";
              mountpoint = "none";
            };
          };
          "safe/data" = {
            type = "zfs_fs";
            mountpoint = "/data";
            options = {
              canmount = "on";
              mountpoint = "/data";
              compression = "zstd-3";
            };
          };

          # Reserved space
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
  };
}
