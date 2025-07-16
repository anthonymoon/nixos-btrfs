# Desktop environment packages
{pkgs, ...}:
with pkgs; [
  # Wayland tools
  wofi
  grim
  slurp
  wl-clipboard
  mako
  xdg-desktop-portal-wlr

  # System tools
  blueman

  # Fonts
  nerd-fonts.fira-code
]
