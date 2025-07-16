{
  config,
  lib,
  pkgs,
  ...
}: {
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      mesa
      amdvlk
      rocm-opencl-icd
      rocm-opencl-runtime
      vulkan-loader
      vulkan-validation-layers
      vulkan-tools
    ];
    extraPackages32 = with pkgs.pkgsi686Linux; [mesa];
  };

  services.xserver.videoDrivers = ["nvidia" "amdgpu"];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    extraCompatPackages = with pkgs; [proton-ge-bin];
  };

  programs.gamemode.enable = true;
  hardware.xpadneo.enable = true;
  services.hardware.openrgb.enable = true;

  services.udev.packages = with pkgs; [game-devices-udev-rules];

  boot.kernelModules = ["uinput" "hid-nintendo" "xpadneo"];
  boot.kernelParams = [
    "amd_pstate=active"
    "amdgpu.ppfeaturemask=0xffffffff"
  ];

  environment.systemPackages = import ../packages/gaming.nix {inherit pkgs;};

  networking.firewall.allowedTCPPorts = [27015 7777 25565];
  networking.firewall.allowedUDPPorts = [27015 7777 34197];
}
