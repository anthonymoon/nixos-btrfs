# Base system configuration
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options.modules.core.base = {
    enable = mkEnableOption "base system configuration";

    systemPackages = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "Additional system packages";
    };
  };

  config = mkIf config.modules.core.base.enable {
    # Essential packages
    environment.systemPackages = with pkgs;
      [
        # Core utilities
        coreutils
        util-linux
        procps
        psmisc

        # System tools
        git
        vim
        wget
        curl
        htop
        btop

        # Modern CLI tools
        fd
        ripgrep
        eza
        bat
        ncdu
        duf

        # File management
        tree
        file
        which
        less

        # Network tools
        iproute2
        iputils
        dig
        nmap

        # System monitoring
        iotop
        lsof
        strace

        # Compression
        gzip
        bzip2
        xz
        zstd
        unzip
        p7zip
      ]
      ++ config.modules.core.base.systemPackages;

    # Enable fish shell
    programs.fish.enable = true;

    # System version
    system.stateVersion = "24.05";
  };
}
