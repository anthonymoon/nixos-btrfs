# Module registry
{lib}: {
  # Core system modules
  core = import ./core;

  # Service modules
  services = import ./services;

  # Hardware modules
  hardware = import ./hardware;

  # Desktop modules
  desktop = import ./desktop;
}
