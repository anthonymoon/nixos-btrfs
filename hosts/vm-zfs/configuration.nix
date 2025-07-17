{
  config,
  pkgs,
  lib,
  ...
}: {
  # Basic VM configuration

  # Minimal headless setup
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Time zone and locale
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  # Enable SSH for headless access
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = lib.mkForce "yes";
      PasswordAuthentication = lib.mkForce true;
    };
  };

  # Create a basic user
  users.users.amoon = {
    isNormalUser = true;
    description = "NixOS User";
    extraGroups = ["wheel"];
    initialPassword = "nixos"; # Change this after installation
  };

  # Allow passwordless sudo for wheel group
  security.sudo.wheelNeedsPassword = false;

  # Minimal packages for headless VM
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tmux
  ];

  # Enable QEMU guest agent
  services.qemuGuest.enable = true;

  # Workaround for btrfsck symlink conflict in NixOS 24.11
  # Use systemd-based initrd if needed: boot.initrd.systemd.enable = true;
  # Alternative: set NIXPKGS_ALLOW_BROKEN=1 during installation

  # Disable GUI
  services.xserver.enable = false;

  # Network configuration
  networking.useDHCP = lib.mkDefault true;

  # ZFS requires a hostId
  networking.hostId = "8425e349";

  # Firewall
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [22];

  system.stateVersion = "24.11";
}
