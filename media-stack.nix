# Media automation stack configuration
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Media services
  services = {
    # Jellyfin - Media server
    jellyfin = {
      enable = true;
      openFirewall = true;
      group = "media";
    };

    # Sonarr - TV show management
    sonarr = {
      enable = true;
      openFirewall = true;
      group = "media";
    };

    # Radarr - Movie management
    radarr = {
      enable = true;
      openFirewall = true;
      group = "media";
    };

    # Lidarr - Music management
    lidarr = {
      enable = true;
      openFirewall = true;
      group = "media";
    };

    # Readarr - Book management
    readarr = {
      enable = true;
      openFirewall = true;
      group = "media";
    };

    # Bazarr - Subtitle management
    bazarr = {
      enable = true;
      openFirewall = true;
      group = "media";
    };

    # Prowlarr - Indexer management
    prowlarr = {
      enable = true;
      openFirewall = true;
    };

    # Jellyseerr - Request management
    jellyseerr = {
      enable = true;
      openFirewall = true;
    };

    # qBittorrent - Torrent client
    qbittorrent = {
      enable = true;
      openFirewall = true;
      port = 8080;
    };

    # Jacket - Additional indexer support (alternative to Prowlarr)
    jackett = {
      enable = true;
      openFirewall = true;
    };

    # FlareSolverr - Cloudflare bypass for indexers
    flaresolverr = {
      enable = true;
      openFirewall = true;
    };

    # Homarr - Beautiful dashboard
    homarr = {
      enable = true;
      openFirewall = true;
    };

    # AdGuard Home - Network-wide ad blocking
    adguardhome = {
      enable = true;
      openFirewall = true;
      settings = {
        bind_host = "0.0.0.0";
        bind_port = 3000;
        dns = {
          bind_host = "0.0.0.0";
          port = 53;
          protection_enabled = true;
          filtering_enabled = true;
          # Upstream DNS servers
          upstream_dns = [
            "https://dns.cloudflare.com/dns-query"
            "https://dns.google/dns-query"
            "tls://1.1.1.1"
            "tls://8.8.8.8"
          ];
          # Bootstrap DNS servers
          bootstrap_dns = [
            "1.1.1.1"
            "8.8.8.8"
          ];
        };
      };
    };

    # Samba - SMB/CIFS file sharing
    samba = {
      enable = true;
      openFirewall = true;

      extraConfig = ''
        workgroup = WORKGROUP
        server string = NixOS Media Server
        netbios name = nixos-media
        security = user

        # Performance optimizations
        socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072
        read raw = yes
        write raw = yes
        use sendfile = yes
        min receivefile size = 16384

        # Enable SMB3
        server min protocol = SMB2
        client min protocol = SMB2

        # VFS modules for better performance
        vfs objects = catia fruit streams_xattr
      '';

      shares = {
        media = {
          path = "/media";
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "create mask" = "0664";
          "directory mask" = "0775";
          "force user" = "media";
          "force group" = "media";
          comment = "Media Library";
        };

        downloads = {
          path = "/media/downloads";
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "create mask" = "0664";
          "directory mask" = "0775";
          "force user" = "media";
          "force group" = "media";
          comment = "Downloads";
        };
      };
    };

    # NFS v4.2 server
    nfs.server = {
      enable = true;
      exports = ''
        /media         *(rw,sync,no_subtree_check,no_root_squash,fsid=0)
        /media/movies  *(rw,sync,no_subtree_check,no_root_squash)
        /media/tv      *(rw,sync,no_subtree_check,no_root_squash)
        /media/music   *(rw,sync,no_subtree_check,no_root_squash)
        /media/downloads *(rw,sync,no_subtree_check,no_root_squash)
      '';

      # Enable NFSv4.2 for better performance
      extraNfsdConfig = ''
        vers4.2=y
      '';
    };

    # Traefik - Modern reverse proxy with auto SSL
    traefik = {
      enable = true;

      staticConfigOptions = {
        global = {
          checkNewVersion = false;
          sendAnonymousUsage = false;
        };

        entryPoints = {
          web = {
            address = ":80";
            http.redirections.entrypoint = {
              to = "websecure";
              scheme = "https";
            };
          };
          websecure = {
            address = ":443";
          };
        };

        certificatesResolvers.letsencrypt.acme = {
          email = "anthony@dirtybit.co";
          storage = "/var/lib/traefik/acme.json";
          httpChallenge.entryPoint = "web";
        };

        api = {
          dashboard = true;
        };
      };

      dynamicConfigOptions = {
        http = {
          routers = {
            # Homarr dashboard
            homarr = {
              rule = "Host(`home.${config.networking.domain}`)";
              service = "homarr";
              tls.certResolver = "letsencrypt";
            };

            # Traefik dashboard
            traefik = {
              rule = "Host(`traefik.${config.networking.domain}`)";
              service = "api@internal";
              tls.certResolver = "letsencrypt";
            };

            # Jellyfin
            jellyfin = {
              rule = "Host(`jellyfin.${config.networking.domain}`)";
              service = "jellyfin";
              tls.certResolver = "letsencrypt";
            };

            # Jellyseerr
            jellyseerr = {
              rule = "Host(`requests.${config.networking.domain}`)";
              service = "jellyseerr";
              tls.certResolver = "letsencrypt";
            };

            # Sonarr
            sonarr = {
              rule = "Host(`tv.${config.networking.domain}`)";
              service = "sonarr";
              tls.certResolver = "letsencrypt";
            };

            # Radarr
            radarr = {
              rule = "Host(`movies.${config.networking.domain}`)";
              service = "radarr";
              tls.certResolver = "letsencrypt";
            };

            # Prowlarr
            prowlarr = {
              rule = "Host(`indexers.${config.networking.domain}`)";
              service = "prowlarr";
              tls.certResolver = "letsencrypt";
            };

            # qBittorrent
            qbittorrent = {
              rule = "Host(`torrents.${config.networking.domain}`)";
              service = "qbittorrent";
              tls.certResolver = "letsencrypt";
            };

            # Lidarr
            lidarr = {
              rule = "Host(`music.${config.networking.domain}`)";
              service = "lidarr";
              tls.certResolver = "letsencrypt";
            };

            # Readarr
            readarr = {
              rule = "Host(`books.${config.networking.domain}`)";
              service = "readarr";
              tls.certResolver = "letsencrypt";
            };

            # Bazarr
            bazarr = {
              rule = "Host(`subtitles.${config.networking.domain}`)";
              service = "bazarr";
              tls.certResolver = "letsencrypt";
            };

            # AdGuard Home
            adguard = {
              rule = "Host(`dns.${config.networking.domain}`)";
              service = "adguard";
              tls.certResolver = "letsencrypt";
            };
          };

          services = {
            homarr.loadBalancer.servers = [{url = "http://localhost:7575";}];
            jellyfin.loadBalancer.servers = [{url = "http://localhost:8096";}];
            jellyseerr.loadBalancer.servers = [{url = "http://localhost:5055";}];
            sonarr.loadBalancer.servers = [{url = "http://localhost:8989";}];
            radarr.loadBalancer.servers = [{url = "http://localhost:7878";}];
            prowlarr.loadBalancer.servers = [{url = "http://localhost:9696";}];
            qbittorrent.loadBalancer.servers = [{url = "http://localhost:8080";}];
            lidarr.loadBalancer.servers = [{url = "http://localhost:8686";}];
            readarr.loadBalancer.servers = [{url = "http://localhost:8787";}];
            bazarr.loadBalancer.servers = [{url = "http://localhost:6767";}];
            adguard.loadBalancer.servers = [{url = "http://localhost:3000";}];
          };
        };
      };
    };
  };

  # Create media group and directories
  users.groups.media = {};

  # System packages for media management
  environment.systemPackages = with pkgs; [
    # Media tools
    ffmpeg-full
    mediainfo
    mkvtoolnix
    handbrake

    # Monitoring
    htop
    iotop
    glances

    # File management
    ncdu
    rsync
    rclone

    # Network tools
    curl
    wget
    aria2
  ];

  # Create media directories with proper permissions
  systemd.tmpfiles.rules = [
    "d /media 0775 root media - -"
    "d /media/movies 0775 root media - -"
    "d /media/tv 0775 root media - -"
    "d /media/music 0775 root media - -"
    "d /media/books 0775 root media - -"
    "d /media/downloads 0775 root media - -"
    "d /media/torrents 0775 root media - -"
    "d /media/torrents/complete 0775 root media - -"
    "d /media/torrents/incomplete 0775 root media - -"
  ];

  # Add user to media group
  users.users.amoon.extraGroups = ["media"];

  # Firewall rules for services
  networking.firewall = {
    allowedTCPPorts = [
      80 # HTTP (Traefik)
      443 # HTTPS (Traefik)
      53 # DNS (AdGuard Home)
      3000 # AdGuard Home Web UI
      139 # SMB
      445 # SMB
      2049 # NFS
      111 # NFS RPC
      7575 # Homarr
      8096 # Jellyfin
      5055 # Jellyseerr
      8989 # Sonarr
      7878 # Radarr
      8686 # Lidarr
      8787 # Readarr
      6767 # Bazarr
      9696 # Prowlarr
      8080 # qBittorrent
      9117 # Jackett
      8191 # FlareSolverr
    ];

    allowedUDPPorts = [
      53 # DNS (AdGuard Home)
      137 # NetBIOS Name Service
      138 # NetBIOS Datagram Service
      2049 # NFS
      111 # NFS RPC
    ];

    # qBittorrent peer ports
    allowedTCPPortRanges = [
      {
        from = 6881;
        to = 6889;
      }
    ];
    allowedUDPPortRanges = [
      {
        from = 6881;
        to = 6889;
      }
    ];
  };

  # Performance optimizations for media services
  boot.kernel.sysctl = {
    # Network optimizations for streaming
    "net.core.wmem_max" = 134217728;
    "net.core.rmem_max" = 134217728;
    "net.ipv4.tcp_wmem" = "4096 65536 134217728";
    "net.ipv4.tcp_rmem" = "4096 65536 134217728";

    # File system optimizations
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 512;
  };

  # Service dependencies and startup order
  systemd.services = {
    sonarr = {
      after = ["prowlarr.service" "qbittorrent.service"];
      wants = ["prowlarr.service" "qbittorrent.service"];
    };

    radarr = {
      after = ["prowlarr.service" "qbittorrent.service"];
      wants = ["prowlarr.service" "qbittorrent.service"];
    };

    jellyseerr = {
      after = ["jellyfin.service"];
      wants = ["jellyfin.service"];
    };
  };
}
