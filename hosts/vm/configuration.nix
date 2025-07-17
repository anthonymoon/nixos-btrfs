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

  # VM guest services (auto-detects virtualization platform)
  services.qemuGuest.enable = true;
  
  # VM optimizations for better performance
  boot.kernelParams = [
    "console=ttyS0"        # Serial console for headless VMs
    "console=tty0"         # Keep local console
  ];
  
  # Hyper-V specific optimizations
  boot.kernelModules = ["hv_vmbus" "hv_balloon" "hv_storvsc" "hv_netvsc"];
  boot.initrd.kernelModules = ["hv_vmbus" "hv_storvsc"];
  
  # Enable Hyper-V guest services
  systemd.services.hv-fcopy = {
    description = "Hyper-V File Copy Service";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = "${pkgs.linuxPackages.hyperv-daemons}/bin/hv_fcopy_daemon -n";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
  
  systemd.services.hv-kvp = {
    description = "Hyper-V Key-Value Pair Service";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = "${pkgs.linuxPackages.hyperv-daemons}/bin/hv_kvp_daemon -n";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
  
  systemd.services.hv-vss = {
    description = "Hyper-V Volume Shadow Copy Service";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = "${pkgs.linuxPackages.hyperv-daemons}/bin/hv_vss_daemon -n";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  # Workaround for btrfsck symlink conflict in NixOS 24.11
  # Use systemd-based initrd if needed: boot.initrd.systemd.enable = true;
  # Alternative: set NIXPKGS_ALLOW_BROKEN=1 during installation

  # Disable GUI
  services.xserver.enable = false;

  # Network configuration
  networking.useDHCP = lib.mkDefault true;

  # Firewall
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [22];

  system.stateVersion = "24.11";
}
