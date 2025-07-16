{
  config,
  lib,
  pkgs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    btrbk
    snapper
  ];

  services.btrbk = {
    instances."btrbk" = {
      onCalendar = "hourly";
      settings = {
        snapshot_preserve_min = "2d";
        snapshot_preserve = "48h 20d 6m";
        target_preserve_min = "no";
        target_preserve = "20d 10w";

        volume."/" = {
          subvolume = {
            "@home" = {
              snapshot_dir = "@snapshots/home";
              snapshot_create = "always";
            };
            "@" = {
              snapshot_dir = "@snapshots/root";
              snapshot_create = "always";
            };
          };
        };
      };
    };
  };

  services.snapper = {
    configs = {
      home = {
        SUBVOLUME = "/home";
        ALLOW_GROUPS = ["wheel"];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_HOURLY = "12";
        TIMELINE_LIMIT_DAILY = "7";
        TIMELINE_LIMIT_WEEKLY = "4";
        TIMELINE_LIMIT_MONTHLY = "6";
        TIMELINE_LIMIT_YEARLY = "0";
      };
    };
  };

  systemd.services.btrbk-boot-snapshot = {
    description = "Create snapshot before boot";
    wantedBy = ["multi-user.target"];
    after = ["local-fs.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.btrbk}/bin/btrbk snapshot";
    };
  };

  environment.etc."btrbk/btrbk.conf.local".text = ''
    snapshot_dir = /.snapshots
    snapshot_preserve_min = latest
    snapshot_preserve = 48h 7d 4w 6m
  '';
}
