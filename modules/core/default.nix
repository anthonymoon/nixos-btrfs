# Core system modules
{
  base = import ./base.nix;
  networking = import ./networking.nix;
  nix = import ./nix.nix;
  users = import ./users.nix;
  boot = import ./boot.nix;
}
