# Hardware configuration merging disko setup with existing config
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [(modulesPath + "/installer/scan/not-detected.nix")];

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    # ZFS configuration
    supportedFilesystems = ["zfs"];
    zfs.forceImportRoot = true;
    zfs.requestEncryptionCredentials = false;

    initrd = {
      availableKernelModules = ["xhci_pci" "ahci" "usb_storage" "usbhid" "sd_mod"];
      kernelModules = ["virtio"];
      supportedFilesystems = ["zfs"];
    };

    kernelParams = [
      "mitigations=off"
      "zfs.zfs_arc_max=2147483648" # 2GB ARC max
    ];

    kernelModules = [
      "kvm-amd"
      "xt_socket"
      "vhost-net"
      "bridge"
      "br_netfilter"
    ];

    extraModulePackages = [];
    kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;

    kernel = {
      sysctl."net.ipv4.ip_forward" = 1;
    };
  };

  # Choose one of these filesystem configurations based on your pool name:

  # Option 1: If using 'rpool' (from the hardware config you provided)
  fileSystems = lib.mkIf (config.networking.hostName == "with-rpool") {
    "/" = {
      device = "rpool/local/root";
      fsType = "zfs";
      neededForBoot = true;
      options = ["zfsutil"];
    };
    "/boot" = {
      device = "/dev/disk/by-label/EFI";
      fsType = "vfat";
    };
    "/nix" = {
      device = "rpool/local/nix";
      fsType = "zfs";
      neededForBoot = true;
    };
    "/nix/store" = {
      device = "rpool/local/nix-store";
      fsType = "zfs";
      neededForBoot = true;
    };
    "/cache" = {
      device = "rpool/local/cache";
      fsType = "zfs";
      neededForBoot = true;
    };
    "/data" = {
      device = "rpool/safe/data";
      fsType = "zfs";
      neededForBoot = true;
    };
  };

  # Option 2: If using 'zroot' (from your current config)
  fileSystems = lib.mkIf (config.networking.hostName != "with-rpool") {
    "/" = {
      device = "zroot/root/nixos";
      fsType = "zfs";
      options = ["zfsutil"];
    };
    "/boot" = {
      device = "/dev/disk/by-label/EFI";
      fsType = "vfat";
    };
    "/home" = {
      device = "zroot/home";
      fsType = "zfs";
    };
    "/nix" = {
      device = "zroot/nix";
      fsType = "zfs";
    };
    "/persist" = {
      device = "zroot/persist";
      fsType = "zfs";
    };
  };

  # Swap configuration - adjust based on your setup
  swapDevices = lib.optional (builtins.pathExists "/dev/disk/by-label/swap") {
    device = "/dev/disk/by-label/swap";
  };

  # Set a proper unique hostId (required for ZFS)
  networking.hostId = "abcd1234"; # Generate with: head -c4 /dev/urandom | od -A none -t x4 | sed 's/ //'

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  hardware = {
    cpu.amd.updateMicrocode = true;
    enableRedistributableFirmware = true;
    graphics.enable = true;

    # NVIDIA configuration
    nvidia = {
      package = config.boot.kernelPackages.nvidiaPackages.latest;
      powerManagement.enable = true;
      open = false;
      modesetting.enable = true;
    };
  };

  services = {
    fstrim.enable = true;
    blueman.enable = true;

    # ZFS services
    zfs.autoScrub.enable = true;
    zfs.autoSnapshot.enable = true;
  };

  # Allow NVIDIA packages
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "nvidia-x11"
      "nvidia"
      "nvidia-settings"
    ];
}
