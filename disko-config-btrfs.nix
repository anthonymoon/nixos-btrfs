# Btrfs configuration with optimized subvolume layout
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
                mountOptions = ["defaults" "umask=0077"];
              };
            };
            swap = {
              size = "8G";
              content = {
                type = "swap";
                randomEncryption = true;
                priority = 100;
              };
            };
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = ["-f"]; # Force creation
                subvolumes = {
                  # Root subvolume
                  "@" = {
                    mountpoint = "/";
                    mountOptions = ["compress=zstd:3" "noatime" "ssd" "space_cache=v2" "discard=async"];
                  };
                  # Home subvolume - separate for snapshots
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = ["compress=zstd:3" "noatime" "ssd" "space_cache=v2" "discard=async"];
                  };
                  # Nix store - high compression, no CoW for better performance
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = ["compress=zstd:6" "noatime" "ssd" "space_cache=v2" "discard=async" "nodatacow"];
                  };
                  # Persistent state
                  "@persist" = {
                    mountpoint = "/persist";
                    mountOptions = ["compress=zstd:3" "noatime" "ssd" "space_cache=v2" "discard=async"];
                  };
                  # Log files - lower compression
                  "@log" = {
                    mountpoint = "/var/log";
                    mountOptions = ["compress=zstd:1" "noatime" "ssd" "space_cache=v2" "discard=async"];
                  };
                  # Cache - no compression
                  "@cache" = {
                    mountpoint = "/var/cache";
                    mountOptions = ["noatime" "ssd" "space_cache=v2" "discard=async" "nodatacow"];
                  };
                  # Snapshots directory
                  "@snapshots" = {
                    mountpoint = "/.snapshots";
                    mountOptions = ["compress=zstd:3" "noatime" "ssd" "space_cache=v2" "discard=async"];
                  };
                  # Swap file subvolume - no compression, no CoW
                  "@swap" = {
                    mountpoint = "/swap";
                    mountOptions = ["noatime" "nodatacow"];
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
