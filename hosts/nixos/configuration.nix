{
  config,
  pkgs,
  lib,
  ...
}: {
  networking.domain = "dirtybit.co";
  networking.hostId = "deadbeef";

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  users.users.amoon = {
    isNormalUser = true;
    description = "Anthony Moon";
    extraGroups = ["wheel" "networkmanager" "video" "audio" "docker" "libvirtd" "kvm"];
    shell = pkgs.fish;
  };

  programs.fish.enable = true;
}
