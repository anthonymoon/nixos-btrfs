{
  config,
  lib,
  pkgs,
  ...
}: {
  virtualisation = {
    libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = false;
        swtpm.enable = true;
        ovmf.enable = true;
      };
    };

    spiceUSBRedirection.enable = true;
  };

  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;

  boot.kernelModules = [
    "kvm-amd"
    "kvm-intel"
    "vfio"
    "vfio_iommu_type1"
    "vfio_pci"
    "vfio_virqfd"
  ];

  environment.systemPackages = with pkgs; [
    virt-manager
    virt-viewer
    spice-gtk
    spice-protocol
    win-virtio
    win-spice
  ];

  # vm.swappiness is set in disko configurations based on filesystem type

  zramSwap = {
    enable = lib.mkDefault true;
    memoryPercent = lib.mkDefault 100;
    algorithm = "zstd";
  };
}
