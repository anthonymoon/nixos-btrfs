{
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
}
