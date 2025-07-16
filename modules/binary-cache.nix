{
  config,
  lib,
  pkgs,
  ...
}: {
  # Binary cache configuration
  nix.settings = {
    substituters = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org"
      "http://cachy.local"
    ];

    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cachy.local:/5+zDOluBKCtE2CdtE/aV4vB1gp1M1HsQFKbfCWKO14="
    ];

    # Note: substituters are tried in order listed above
    # Local cache is listed last but will be tried first due to network proximity

    # Additional cache settings
    connect-timeout = 60;

    # Enable parallel downloads
    max-substitution-jobs = 16;
  };

  # Enable distributed builds (optional)
  nix.distributedBuilds = lib.mkDefault false;

  # Optional: Configure build machine for distributed builds
  nix.buildMachines = lib.mkIf config.nix.distributedBuilds [
    {
      hostName = "cachy.local";
      system = "x86_64-linux";
      maxJobs = 4;
      speedFactor = 2;
      supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm"];
      mandatoryFeatures = [];
      sshUser = "nix-serve";
      sshKey = "/etc/nix/id_buildfarm";
    }
  ];

  # Environment variable for cache management scripts
  environment.variables = {
    CACHE_URL = "http://cachy.local";
  };

  # Add cache management utilities to system packages
  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "cache-push" ''
      #!/usr/bin/env bash
      # Push store path to local cache
      if [[ -z "$1" ]]; then
        echo "Usage: cache-push <store-path>"
        exit 1
      fi
      nix copy --to http://cachy.local "$1"
    '')

    (writeShellScriptBin "cache-test" ''
      #!/usr/bin/env bash
      # Test cache connectivity
      if curl -s --connect-timeout 5 http://cachy.local/nix-cache-info > /dev/null; then
        echo "✓ Cache is reachable"
        curl -s http://cachy.local/nix-cache-info
      else
        echo "✗ Cache is not reachable"
        exit 1
      fi
    '')

    (writeShellScriptBin "cache-stats" ''
      #!/usr/bin/env bash
      # Show cache statistics
      echo "=== Local Cache Statistics ==="
      echo "Store paths: $(nix path-info --all | wc -l)"
      echo "Store size: $(du -sh /nix/store 2>/dev/null | cut -f1)"
      echo ""
      echo "=== Remote Cache Info ==="
      curl -s http://cachy.local/nix-cache-info 2>/dev/null || echo "Cache not available"
    '')
  ];
}
