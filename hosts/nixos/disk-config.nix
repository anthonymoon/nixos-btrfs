# Disk configuration using disko
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda"; # Change this to your disk
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
                mountOptions = ["umask=0077"];
              };
            };
            swap = {
              size = "16G";
              content = {
                type = "swap";
                randomEncryption = false;
              };
            };
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = ["-f"];
                subvolumes = {
                  "@" = {
                    mountpoint = "/";
                    mountOptions = ["compress=zstd:3" "noatime" "ssd" "space_cache=v2" "discard=async"];
                  };
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = ["compress=zstd:3" "noatime" "ssd" "space_cache=v2" "discard=async"];
                  };
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = ["compress=zstd:6" "noatime" "ssd" "space_cache=v2" "discard=async"];
                  };
                  "@var" = {
                    mountpoint = "/var";
                    mountOptions = ["compress=zstd:3" "noatime" "ssd" "space_cache=v2" "discard=async"];
                  };
                  "@tmp" = {
                    mountpoint = "/tmp";
                    mountOptions = ["compress=zstd:1" "noatime" "ssd" "space_cache=v2" "discard=async"];
                  };
                  "@snapshots" = {
                    mountpoint = "/.snapshots";
                    mountOptions = ["compress=zstd:3" "noatime" "ssd" "space_cache=v2" "discard=async"];
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
