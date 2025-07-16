# Gaming and development stack configuration
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Allow unfree packages for proprietary software
  nixpkgs.config.allowUnfree = true;

  # Enable 32-bit support for gaming
  hardware.graphics = {
    enable = true;
    enable32Bit = true;

    # AMD GPU support with latest Mesa
    extraPackages = with pkgs; [
      mesa
      amdvlk
      rocm-opencl-icd
      rocm-opencl-runtime
    ];
    extraPackages32 = with pkgs.pkgsi686Linux; [
      mesa
    ];
  };

  # NVIDIA proprietary drivers (comment out if using AMD only)
  services.xserver.videoDrivers = ["nvidia" "amdgpu"];
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = false;
    open = false; # Use closed source driver
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # Gaming support
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };

  programs.gamemode.enable = true;

  # Controller support
  hardware.xpadneo.enable = true; # Xbox wireless controller support
  services.hardware.openrgb.enable = true;

  # Enable udev rules for controllers
  services.udev.packages = with pkgs; [
    game-devices-udev-rules # PS5 DualSense and other controllers
  ];

  # System packages
  environment.systemPackages = with pkgs; [
    # Browsers
    thorium # Chromium-based optimized browser
    microsoft-edge
    tor-browser-bundle-bin
    zen-browser

    # Development tools
    vscode-insiders
    terraform
    google-cloud-sdk
    python312
    python312Packages.pip
    python312Packages.virtualenv

    # AI tools
    # claude-code # Would need custom derivation
    # gemini-cli # Would need custom derivation

    # Media tools
    mpv
    ffmpeg-full

    # Audio processing
    rnnoise
    noisetorch
    cava # Audio visualizer

    # Communication
    slack
    signal-desktop
    whatsappforlinux

    # Gaming tools
    gamescope
    mangohud
    goverlay # MangoHud GUI
    protonup-qt
    protontricks
    wine-staging
    winetricks

    # Gaming platforms
    lutris
    bottles
    heroic # Epic Games, GOG, Amazon Games

    # Emulation
    mame
    (retroarch.override {
      cores = with libretro; [
        mame
        fbneo # FightCade games
      ];
    })

    # Vulkan tools
    vulkan-tools
    vulkan-validation-layers
    vkd3d
    vkd3d-proton

    # System monitoring
    nvtop # GPU monitoring
    radeontop # AMD GPU monitoring

    # Additional gaming dependencies
    gamemode
    gamescope
    steamtinkerlaunch
  ];

  # Python 3.12 as default
  programs.python = {
    enable = true;
    package = pkgs.python312;
  };

  # Steam configuration
  programs.steam.extraCompatPackages = with pkgs; [
    proton-ge-bin
  ];

  # Enable Vulkan
  hardware.graphics.extraPackages = with pkgs; [
    vulkan-loader
    vulkan-validation-layers
    vulkan-tools
  ];

  # Kernel modules for gaming
  boot.kernelModules = ["uinput" "hid-nintendo" "xpadneo"];

  # Gaming-optimized kernel parameters
  boot.kernelParams = [
    "amd_pstate=active"
    "amdgpu.ppfeaturemask=0xffffffff"
    "radeon.si_support=0"
    "amdgpu.si_support=1"
    "radeon.cik_support=0"
    "amdgpu.cik_support=1"
  ];

  # Services for gaming
  services = {
    # Feral GameMode
    gamemode = {
      enable = true;
      settings = {
        general = {
          renice = 10;
          inhibit_screensaver = 1;
        };
        gpu = {
          apply_gpu_optimisations = "accept-responsibility";
          gpu_device = 0;
          amd_performance_level = "high";
        };
      };
    };

    # Enable ratbagd for gaming mice
    ratbagd.enable = true;
  };

  # Firewall exceptions for gaming
  networking.firewall = {
    allowedTCPPorts = [
      27015 # Steam
      7777 # Common game server
      25565 # Minecraft
    ];
    allowedUDPPorts = [
      27015 # Steam
      7777 # Common game server
      34197 # Factorio
    ];
  };
}
