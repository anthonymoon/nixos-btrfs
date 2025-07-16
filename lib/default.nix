# Custom library functions
{lib}: rec {
  # Helper to create a NixOS system configuration
  mkHost = {
    hostname,
    system ? "x86_64-linux",
    modules ? [],
  }: {
    inherit system;
    specialArgs = {inherit lib;};
    modules = modules;
  };

  # Helper to merge module lists
  mkModuleList = modules: lib.flatten modules;

  # Check if running in VM
  isVirtualMachine = config:
    config.virtualisation.hypervGuest.enable or false
    || config.services.qemuGuest.enable or false;

  # Helper for creating user configurations
  mkUser = {
    name,
    groups ? [],
    shell ? null,
    description ? "",
  }: {
    isNormalUser = true;
    inherit name description groups;
    shell =
      if shell != null
      then shell
      else null;
  };
}
