{
  config,
  lib,
  pkgs,
  ...
}: {
  programs.hyprland.enable = true;

  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd Hyprland";
        user = "greeter";
      };
    };
  };

  hardware.graphics.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  xdg.portal = {
    enable = true;
    extraPortals = [pkgs.xdg-desktop-portal-wlr];
  };

  environment.systemPackages = with pkgs;
    [
      wofi
      waybar
      mako
      grim
      slurp
      wl-clipboard
      pavucontrol
      blueman
      kitty
      dolphin
    ]
    ++ (import ../packages/desktop.nix {inherit pkgs;});
}
