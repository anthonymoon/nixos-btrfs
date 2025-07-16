{
  config,
  pkgs,
  ...
}: {
  home.username = "amoon";
  home.homeDirectory = "/home/amoon";
  home.stateVersion = "24.05";

  programs.git = {
    enable = true;
    userName = "Anthony Moon";
    userEmail = "anthony@dirtybit.co";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = false;
    };
  };

  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting
    '';
    shellAliases = {
      ll = "eza -la";
      cat = "bat";
      find = "fd";
      grep = "rg";
      bstat = "sudo btrfs filesystem show";
      blist = "sudo btrfs subvolume list /";
      bdf = "sudo btrfs filesystem df /";
    };
  };

  programs.starship = {
    enable = true;
    settings = {
      format = "$all$character";
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[➜](bold red)";
      };
    };
  };

  programs.kitty = {
    enable = true;
    settings = {
      font_family = "FiraCode Nerd Font";
      font_size = 12;
      background_opacity = "0.9";
      window_padding_width = 10;
    };
  };

  wayland.windowManager.hyprland = {
    enable = true;
    settings = import ./config/hyprland.nix;
  };

  programs.waybar = {
    enable = true;
    settings = import ./config/waybar.nix;
    style = import ./config/waybar-style.nix;
  };

  home.packages = with pkgs;
    [
      btop
      broot
      nnn
      xplr
    ]
    ++ (import ./packages/development.nix {inherit pkgs;})
    ++ (import ./packages/browsers.nix {inherit pkgs;})
    ++ (import ./packages/communication.nix {inherit pkgs;})
    ++ (import ./packages/media.nix {inherit pkgs;});

  xdg.enable = true;
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "thorium.desktop";
      "x-scheme-handler/http" = "thorium.desktop";
      "x-scheme-handler/https" = "thorium.desktop";
    };
  };

  services.mako = {
    enable = true;
    defaultTimeout = 5000;
    backgroundColor = "#2b303b";
    textColor = "#ffffff";
    borderColor = "#65737e";
    borderRadius = 5;
  };

  programs.home-manager.enable = true;
}
