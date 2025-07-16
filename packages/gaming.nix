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

  # Wine/Proton
  wine-staging
  winetricks
  protonup-qt
  protontricks

  # Emulation
  mame
  (retroarch.override {
    cores = with libretro; [
      mame
      fbneo
    ];
  })

  # Performance monitoring
  nvtop
  radeontop

  # Additional tools
  steamtinkerlaunch
]
