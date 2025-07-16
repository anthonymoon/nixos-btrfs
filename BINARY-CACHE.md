# Binary Cache Setup Guide

This guide explains how to set up a local binary cache using nix-serve on Arch Linux and integrate it with your NixOS configuration.

## Overview

A binary cache stores pre-built Nix packages, eliminating the need to rebuild packages from source. This significantly speeds up deployments and reduces build times.

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   NixOS Client  │───▶│  cachy.local    │───▶│  Public Caches  │
│   (deadbeef)    │    │  (Binary Cache) │    │  (cache.nixos.org)
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │   nix-serve     │
                       │   nginx         │
                       │   /nix/store    │
                       └─────────────────┘
```

## Installation

### Step 1: Install nix-serve on Arch Linux (cachy.local)

```bash
# On cachy.local (Arch Linux)
cd /path/to/nixos-btrfs
./scripts/install-nix-serve-arch.sh
```

This script will:
- Install Nix, nix-serve, and nginx
- Generate signing keys for the binary cache
- Configure systemd service for nix-serve
- Set up nginx as reverse proxy
- Optionally configure SSL with Let's Encrypt

### Step 2: Configure NixOS Integration

```bash
# On your NixOS system or locally
./scripts/configure-binary-cache.sh
```

This script will:
- Test connectivity to the binary cache
- Create binary cache configuration module
- Update flake.nix to include the module
- Create cache management utilities

### Step 3: Deploy Configuration

```bash
# Deploy the updated configuration
sudo nixos-rebuild switch --flake .#nixos
```

## Configuration Details

### Binary Cache Server (cachy.local)

**Service Configuration:**
- **URL**: `http://cachy.local` (or `https://cachy.local` with SSL)
- **Port**: 5000 (internal), 80/443 (nginx proxy)
- **User**: `nix-serve`
- **Keys**: `/var/lib/nix-serve/cache-{priv,pub}-key.pem`

**Systemd Service:**
```bash
# Check service status
sudo systemctl status nix-serve

# View logs
sudo journalctl -u nix-serve -f

# Restart service
sudo systemctl restart nix-serve
```

### NixOS Client Configuration

The binary cache is configured in `modules/binary-cache.nix`:

```nix
nix.settings = {
  substituters = [
    "https://cache.nixos.org/"
    "https://nix-community.cachix.org"
    "http://cachy.local"
  ];
  
  trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "cachy.local:YOUR_PUBLIC_KEY_HERE"
  ];
};
```

## Usage

### Cache Management

Use the cache management script for common operations:

```bash
# Test cache connectivity
./scripts/cache-management.sh test

# Show cache status
./scripts/cache-management.sh status

# View cache information
./scripts/cache-management.sh info

# Push a store path to cache
./scripts/cache-management.sh push /nix/store/hash-package-version

# Show cache statistics
./scripts/cache-management.sh stats

# Clear local cache
./scripts/cache-management.sh clear
```

### Building and Caching

When you build packages, they're automatically cached:

```bash
# Build system (automatically uses and populates cache)
sudo nixos-rebuild switch --flake .#nixos

# Build specific package
nix build .#packages.x86_64-linux.some-package

# Manually copy to cache
nix copy --to http://cachy.local /nix/store/hash-package-version
```

### Monitoring

Monitor cache usage and performance:

```bash
# Cache server logs
sudo journalctl -u nix-serve -f

# Nginx access logs
sudo tail -f /var/log/nginx/access.log

# Cache statistics
./scripts/cache-management.sh stats

# Network usage
iftop -i eth0
```

## Troubleshooting

### Common Issues

**Cache not reachable:**
```bash
# Check if nix-serve is running
sudo systemctl status nix-serve

# Check nginx configuration
sudo nginx -t

# Test local connection
curl http://localhost:5000/nix-cache-info
```

**Permission denied:**
```bash
# Fix nix-serve permissions
sudo chown -R nix-serve:nix-serve /var/lib/nix-serve

# Restart service
sudo systemctl restart nix-serve
```

**SSL certificate issues:**
```bash
# Renew Let's Encrypt certificate
sudo certbot renew

# Check certificate status
sudo certbot certificates
```

### Performance Tuning

**Nginx optimization:**
```nginx
# Add to /etc/nginx/sites-available/nix-serve
location / {
    proxy_pass http://127.0.0.1:5000;
    proxy_buffering on;
    proxy_buffer_size 4k;
    proxy_buffers 8 4k;
    proxy_busy_buffers_size 8k;
    
    # Increase timeouts for large packages
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
}
```

**nix-serve optimization:**
```bash
# Increase worker processes
sudo systemctl edit nix-serve

# Add:
[Service]
Environment="NIX_SERVE_WORKERS=4"
```

## Security Considerations

### Network Security

- **Firewall**: Only open port 80/443 externally
- **SSL**: Use Let's Encrypt for production
- **Access Control**: Restrict access to trusted networks

### Key Management

- **Private Key**: Keep `/var/lib/nix-serve/cache-priv-key.pem` secure
- **Public Key**: Share `/var/lib/nix-serve/cache-pub-key.pem` with clients
- **Rotation**: Regenerate keys periodically

### Monitoring

- **Logs**: Monitor access logs for suspicious activity
- **Usage**: Track cache usage patterns
- **Alerts**: Set up alerts for service failures

## Maintenance

### Regular Tasks

**Daily:**
- Check service status
- Monitor disk usage
- Review access logs

**Weekly:**
- Update nix-serve and dependencies
- Check SSL certificate expiry
- Clean old cached packages

**Monthly:**
- Review cache statistics
- Optimize nginx configuration
- Update documentation

### Backup Strategy

```bash
# Backup signing keys
sudo cp /var/lib/nix-serve/cache-*-key.pem /backup/location/

# Backup configuration
sudo cp /etc/systemd/system/nix-serve.service /backup/location/
sudo cp /etc/nginx/sites-available/nix-serve /backup/location/
```

## Advanced Configuration

### Multiple Cache Servers

Configure multiple cache servers for redundancy:

```nix
nix.settings.substituters = [
  "https://cache.nixos.org/"
  "http://cachy.local"
  "http://cachy2.local"
  "http://cachy3.local"
];
```

### Build Farm Integration

Use the cache server as part of a build farm:

```nix
nix.distributedBuilds = true;
nix.buildMachines = [{
  hostName = "cachy.local";
  system = "x86_64-linux";
  maxJobs = 4;
  speedFactor = 2;
  supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm"];
}];
```

## References

- [Nix Manual - Binary Cache](https://nixos.org/manual/nix/stable/package-management/binary-cache.html)
- [NixOS Wiki - Binary Cache](https://nixos.wiki/wiki/Binary_Cache)
- [nix-serve Documentation](https://github.com/edolstra/nix-serve)
- [Cachix Documentation](https://docs.cachix.org/)

---

*For issues or questions, check the troubleshooting section or consult the NixOS community.*