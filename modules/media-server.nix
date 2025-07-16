{
  config,
  lib,
  pkgs,
  ...
}: {
  users.groups.media = {};

  services = {
    jellyfin.enable = true;

    radarr = {
      enable = true;
      group = "media";
    };

    sonarr = {
      enable = true;
      group = "media";
    };

    prowlarr.enable = true;
    bazarr.enable = true;
    lidarr.enable = true;
    readarr.enable = true;

    jellyseerr = {
      enable = true;
      port = 5055;
    };

    transmission = {
      enable = true;
      group = "media";
      settings = {
        download-dir = "/media/downloads";
        incomplete-dir = "/media/downloads/.incomplete";
        rpc-whitelist = "127.0.0.1,192.168.*.*";
        umask = 2;
      };
    };

    adguardhome = {
      enable = true;
      mutableSettings = false;
      host = "0.0.0.0";
      port = 3000;
      settings = {
        dns = {
          bind_hosts = ["0.0.0.0"];
          port = 53;
          upstream_dns = ["94.140.14.14" "94.140.15.15"];
          bootstrap_dns = ["9.9.9.9" "1.1.1.1"];
        };
      };
    };

    samba = {
      enable = true;
      settings = {
        global = {
          "workgroup" = "WORKGROUP";
          "server string" = "deadbeef";
          "security" = "user";
        };
        media = {
          path = "/media";
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "create mask" = "0644";
          "directory mask" = "0755";
        };
      };
    };

    nfs.server = {
      enable = true;
      exports = ''
        /media 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
      '';
    };

    traefik = {
      enable = true;
      staticConfigOptions = {
        entryPoints = {
          web.address = ":80";
          websecure.address = ":443";
        };
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /media 0775 root media -"
    "d /media/downloads 0775 root media -"
    "d /media/tv 0775 root media -"
    "d /media/movies 0775 root media -"
    "d /media/music 0775 root media -"
    "d /media/books 0775 root media -"
  ];

  networking.firewall = {
    allowedTCPPorts = [
      80
      443
      8096
      7878
      8989
      9696
      8787
      8686
      6767
      5055
      9091
      139
      445
      2049
      111
      20048
      3000
      53
    ];
    allowedUDPPorts = [53 137 138];
  };
}
