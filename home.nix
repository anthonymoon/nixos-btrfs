{
  config,
  pkgs,
  ...
}: {
  # User information
  home.username = "amoon";
  home.homeDirectory = "/home/amoon";
  home.stateVersion = "24.05";

  # Git configuration
  programs.git = {
    enable = true;
    userName = "Anthony Moon";
    userEmail = "anthony@dirtybit.co";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = false;
    };
  };

  # Shell configuration
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting # Disable greeting
    '';
    shellAliases = {
      ll = "eza -la";
      cat = "bat";
      find = "fd";
      grep = "rg";
      # Btrfs aliases
      bstat = "sudo btrfs filesystem show";
      blist = "sudo btrfs subvolume list /";
      bdf = "sudo btrfs filesystem df /";
      bsnap = "sudo snapper -c home list";
    };
  };

  # Starship prompt
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

  # Terminal
  programs.kitty = {
    enable = true;
    settings = {
      font_family = "FiraCode Nerd Font";
      font_size = 12;
      background_opacity = "0.9";
      window_padding_width = 10;
    };
  };

  # Hyprland configuration
  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      # Monitor configuration
      monitor = ",preferred,auto,auto";

      # Input configuration
      input = {
        kb_layout = "us";
        follow_mouse = 1;
        touchpad = {
          natural_scroll = false;
        };
        sensitivity = 0;
      };

      # General configuration
      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        "col.active_border" = "rgba(33ccffee) rgba(00ff99ee) 45deg";
        "col.inactive_border" = "rgba(595959aa)";
        layout = "dwindle";
      };

      # Decoration
      decoration = {
        rounding = 5;
        shadow_range = 4;
        shadow_render_power = 3;
        "col.shadow" = "rgba(1a1a1aee)";
      };

      # Animations
      animations = {
        enabled = true;
        bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";
        animation = [
          "windows, 1, 7, myBezier"
          "windowsOut, 1, 7, default, popin 80%"
          "border, 1, 10, default"
          "borderangle, 1, 8, default"
          "fade, 1, 7, default"
          "workspaces, 1, 6, default"
        ];
      };

      # Dwindle layout
      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };

      # Key bindings
      bind = [
        # System
        "SUPER, Return, exec, kitty"
        "SUPER, Q, killactive"
        "SUPER, M, exit"
        "SUPER, E, exec, dolphin"
        "SUPER, V, togglefloating"
        "SUPER, R, exec, wofi --show drun"
        "SUPER, P, pseudo"
        "SUPER, J, togglesplit"

        # Move focus
        "SUPER, left, movefocus, l"
        "SUPER, right, movefocus, r"
        "SUPER, up, movefocus, u"
        "SUPER, down, movefocus, d"

        # Switch workspaces
        "SUPER, 1, workspace, 1"
        "SUPER, 2, workspace, 2"
        "SUPER, 3, workspace, 3"
        "SUPER, 4, workspace, 4"
        "SUPER, 5, workspace, 5"
        "SUPER, 6, workspace, 6"
        "SUPER, 7, workspace, 7"
        "SUPER, 8, workspace, 8"
        "SUPER, 9, workspace, 9"
        "SUPER, 0, workspace, 10"

        # Move to workspace
        "SUPER SHIFT, 1, movetoworkspace, 1"
        "SUPER SHIFT, 2, movetoworkspace, 2"
        "SUPER SHIFT, 3, movetoworkspace, 3"
        "SUPER SHIFT, 4, movetoworkspace, 4"
        "SUPER SHIFT, 5, movetoworkspace, 5"
        "SUPER SHIFT, 6, movetoworkspace, 6"
        "SUPER SHIFT, 7, movetoworkspace, 7"
        "SUPER SHIFT, 8, movetoworkspace, 8"
        "SUPER SHIFT, 9, movetoworkspace, 9"
        "SUPER SHIFT, 0, movetoworkspace, 10"

        # Special keys
        ", Print, exec, grim -g \"$(slurp)\" - | wl-copy"
      ];

      # Mouse bindings
      bindm = [
        "SUPER, mouse:272, movewindow"
        "SUPER, mouse:273, resizewindow"
      ];

      # Window rules
      windowrule = [
        "float, ^(pavucontrol)$"
        "float, ^(blueman-manager)$"
      ];

      # Autostart
      exec-once = [
        "waybar"
        "mako"
      ];
    };
  };

  # Waybar
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 30;
        modules-left = ["hyprland/workspaces"];
        modules-center = ["hyprland/window"];
        modules-right = ["network" "cpu" "memory" "clock" "tray"];

        "hyprland/workspaces" = {
          disable-scroll = true;
          all-outputs = true;
        };

        network = {
          format-wifi = " {signalStrength}%";
          format-ethernet = " {ifname}";
          format-disconnected = "⚠ Disconnected";
          tooltip-format = "{ifname}: {ipaddr}";
        };

        cpu = {
          format = " {usage}%";
          tooltip = false;
        };

        memory = {
          format = " {}%";
        };

        clock = {
          tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
          format-alt = "{:%Y-%m-%d}";
        };
      };
    };
    style = ''
      * {
        border: none;
        border-radius: 0;
        font-family: "FiraCode Nerd Font";
        font-size: 13px;
        min-height: 0;
      }

      window#waybar {
        background-color: rgba(43, 48, 59, 0.9);
        border-bottom: 3px solid rgba(100, 114, 125, 0.5);
        color: #ffffff;
      }

      .modules-left, .modules-center, .modules-right {
        margin: 0 5px;
      }

      #workspaces button {
        padding: 0 5px;
        background-color: transparent;
        color: #ffffff;
        border-bottom: 3px solid transparent;
      }

      #workspaces button:hover {
        background: rgba(0, 0, 0, 0.2);
      }

      #workspaces button.focused {
        background-color: #64727D;
        border-bottom: 3px solid #ffffff;
      }
    '';
  };

  # Development tools - stable versions only
  home.packages = with pkgs; [
    # Terminal tools
    eza
    bat
    fd
    ripgrep
    htop
    btop
    ncdu
    tree
    jq
    yq

    # File management
    broot
    ranger

    # Development
    vscode
    vscode-insiders
    git-crypt
    helix # Modal editor
    evil-helix # Helix with evil mode
    neovim
    zed-editor # High-performance collaborative editor

    # Cloud and DevOps
    terraform
    google-cloud-sdk
    kubectl
    kubernetes-helm

    # Programming languages
    python312
    python312Packages.pip
    python312Packages.virtualenv
    nodejs_20
    rustup

    # Browsers
    thorium
    microsoft-edge
    tor-browser-bundle-bin
    zen-browser

    # Media
    mpv
    ffmpeg-full
    pavucontrol
    cava # Audio visualizer

    # Audio processing
    rnnoise
    noisetorch

    # System tools
    blueman
    compsize # Btrfs compression analyzer
    snapper # Snapshot management

    # Gaming tools (if gaming stack is enabled)
    gamescope
    mangohud
    goverlay

    # System monitoring
    nvtop
    radeontop

    # Wayland tools
    wofi
    grim
    slurp
    wl-clipboard
    mako
    xdg-desktop-portal-wlr # Screen sharing and desktop portal for wlroots

    # Communication
    telegram-desktop
    slack
    signal-desktop
    whatsappforlinux
    discord

    # Fonts
    nerd-fonts.fira-code
  ];

  # XDG configuration
  xdg.enable = true;
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "firefox.desktop";
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "x-scheme-handler/about" = "firefox.desktop";
      "x-scheme-handler/unknown" = "firefox.desktop";
    };
  };

  # Services
  services.mako = {
    enable = true;
    settings = {
      default-timeout = 5000;
      background-color = "#2b303b";
      text-color = "#ffffff";
      border-color = "#65737e";
      border-radius = 5;
    };
  };

  # Let Home Manager install and manage itself
  programs.home-manager.enable = true;
}
