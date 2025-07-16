# Gaming-specific packages
{pkgs, ...}:
with pkgs; [
  # Gaming platforms
  steam
  lutris
  bottles
  heroic

  # Gaming tools
  gamescope
  mangohud
  goverlay
  gamemode

  # Wine/Proton managed by Lutris/Bottles
  protonup-qt
  protontricks

  # Emulation
  (retroarch.override {
    cores = with libretro; [
      mame
      fbneo
    ];
  })

  # Performance monitoring
  nvtopPackages.full
  radeontop

  # Additional tools
  steamtinkerlaunch
]
