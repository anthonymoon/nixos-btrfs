# Hardware configuration for QEMU VM with rpool
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
    zfs.extraPools = ["rpool"]; # Import rpool at boot

    initrd = {
      availableKernelModules = ["virtio_pci" "virtio_blk" "virtio_net" "virtio_balloon"];
      kernelModules = ["virtio"];
      supportedFilesystems = ["zfs"];
    };

    kernelParams = [
      "console=ttyS0,115200" # QEMU serial console
      "zfs.zfs_arc_max=1073741824" # 1GB ARC max for VM
    ];

    kernelModules = [
      "virtio_balloon"
      "virtio_console"
      "virtio_rng"
    ];

    extraModulePackages = [];
    kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
  };

  # Filesystem configuration for rpool
  fileSystems = {
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

  # Swap configuration
  swapDevices = lib.optional (builtins.pathExists "/dev/disk/by-label/swap") {
    device = "/dev/disk/by-label/swap";
  };

  # Set a proper unique hostId (required for ZFS)
  networking.hostId = "abcd1234"; # Generate with: head -c4 /dev/urandom | od -A none -t x4 | sed 's/ //'

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # QEMU guest configuration
  virtualisation.qemu.guestAgent.enable = true;

  hardware = {
    enableRedistributableFirmware = true;
    graphics = {
      enable = true;
      extraPackages = with pkgs; [
        mesa.drivers
      ];
    };
  };

  services = {
    # QEMU guest services
    qemuGuest.enable = true;
    spice-vdagentd.enable = true;

    # ZFS services
    zfs.autoScrub.enable = true;
    zfs.autoSnapshot.enable = true;

    # Disable services not needed in VM
    fstrim.enable = false;
  };
}
