# Media tools
{pkgs, ...}:
with pkgs; [
  # Video/Audio players
  mpv

  # Media processing
  ffmpeg-full

  # Audio tools
  pavucontrol
  cava # Audio visualizer
  rnnoise
  noisetorch

  # Image tools
  imagemagick
  gimp
]
