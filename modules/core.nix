{
  config,
  lib,
  pkgs,
  ...
}: {
  environment.systemPackages = with pkgs;
    [
      coreutils
      git
      vim
      wget
      curl
      htop
      btop
      fd
      ripgrep
      eza
      bat
      ncdu
      duf
      tree
      file
      less
      iproute2
      iputils
      dig
      lsof
      iotop
      gzip
      bzip2
      xz
      zstd
      unzip
      p7zip
    ]
    ++ (import ../packages/base.nix {inherit pkgs;});

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  security.sudo.wheelNeedsPassword = false;
}
