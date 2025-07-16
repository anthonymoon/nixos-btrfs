{
  config,
  lib,
  pkgs,
  ...
}: {
  environment.systemPackages = with pkgs;
    [
      # Version control
      gh
      lazygit
      git-lfs

      # Editors
      vscode-fhs
      neovim

      # Languages
      python312
      nodejs_22
      go
      rustup
      gcc

      # Tools
      docker-compose
      terraform
      google-cloud-sdk
      awscli2
      azure-cli
      httpie
      curl
      wget
      jq
      yq
      gnumake
      cmake
      ninja

      # Database clients
      postgresql
      sqlite
      dbeaver
    ]
    ++ (import ../packages/development.nix {inherit pkgs;});

  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    storageDriver = "btrfs";
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
