{
  config,
  lib,
  pkgs,
  ...
}: {
  networking = {
    networkmanager.enable = false;
    useNetworkd = true;
    useDHCP = false;
    nameservers = ["94.140.14.14" "94.140.15.15"];
    firewall.enable = true;
  };

  systemd.network = {
    enable = true;
    networks."10-ethernet" = {
      matchConfig.Type = "ether";
      DHCP = "yes";
      dhcpV4Config.UseDNS = false;
      dhcpV6Config.UseDNS = false;
    };
  };
}
