{
  lib,
  pkgs,
  ...
}: rec {
  # Get disk information using lsblk (evaluation-time safe version)
  getDiskInfo = disk: let
    # Create a derivation that runs lsblk and returns JSON
    diskInfoDrv = pkgs.runCommand "disk-info-${builtins.baseNameOf disk}" {} ''
      if [[ -b "${disk}" ]]; then
        ${pkgs.util-linux}/bin/lsblk -J -b -o NAME,SIZE,TYPE,TRAN,ROTA,MODEL "${disk}" > $out 2>/dev/null || echo '{"blockdevices":[]}' > $out
      else
        echo '{"blockdevices":[]}' > $out
      fi
    '';
  in
    # Read and parse the JSON at evaluation time
    builtins.fromJSON (builtins.readFile diskInfoDrv);

  # Get all available disks by scanning /dev/disk/by-id at evaluation time
  getAllDisks = {
    excludeRemovable ? true,
    excludeLoop ? true,
    excludePartitions ? true,
  }: let
    # Create a derivation that scans for disks
    diskScanDrv = pkgs.runCommand "scan-disks" {} ''
      # Find all disks in /dev/disk/by-id
      find /dev/disk/by-id -type l | while read disk; do
        # Skip partitions if requested
        if [[ "${toString excludePartitions}" == "true" ]] && [[ "$disk" =~ -part[0-9]+$ ]]; then
          continue
        fi

        # Skip loop devices if requested
        if [[ "${toString excludeLoop}" == "true" ]] && [[ "$disk" =~ loop ]]; then
          continue
        fi

        # Resolve symlink to actual device
        device=$(readlink -f "$disk")

        # Skip if device doesn't exist
        [[ -b "$device" ]] || continue

        # Check if removable
        if [[ "${toString excludeRemovable}" == "true" ]]; then
          removable_file="/sys/block/$(basename "$device")/removable"
          if [[ -f "$removable_file" ]] && [[ "$(cat "$removable_file")" == "1" ]]; then
            continue
          fi
        fi

        echo "$device"
      done | sort -u > $out
    '';
  in
    lib.splitString "\n" (lib.removeSuffix "\n" (builtins.readFile diskScanDrv));

  # Smart primary disk detection with scoring
  detectPrimaryDisk = {
    preferNvme ? true,
    preferSSD ? true,
    minSizeGB ? 20,
    excludeDisks ? [],
    fallbackDisk ? "/dev/sda",
  }: let
    # Create a derivation that detects the best disk
    detectDrv = pkgs.runCommand "detect-primary-disk" {} ''
      best_disk=""
      best_score=0

      # Scan all disks
      for disk_link in /dev/disk/by-id/*; do
        # Skip partitions
        [[ "$disk_link" =~ -part[0-9]+$ ]] && continue

        # Skip loop and other virtual devices
        [[ "$disk_link" =~ (loop|dm-|md) ]] && continue

        # Resolve to actual device
        device=$(readlink -f "$disk_link")
        [[ -b "$device" ]] || continue

        # Skip excluded disks
        excluded=false
        ${lib.concatMapStrings (disk: ''
          [[ "$device" == "${disk}" ]] && excluded=true
        '')
        excludeDisks}
        [[ "$excluded" == "true" ]] && continue

        # Skip removable devices
        removable_file="/sys/block/$(basename "$device")/removable"
        if [[ -f "$removable_file" ]] && [[ "$(cat "$removable_file")" == "1" ]]; then
          continue
        fi

        # Get disk size in GB
        size_bytes=$(blockdev --getsize64 "$device" 2>/dev/null || echo 0)
        size_gb=$((size_bytes / 1073741824))

        # Skip if too small
        [[ $size_gb -lt ${toString minSizeGB} ]] && continue

        # Calculate score
        score=$size_gb

        # Bonus for NVMe
        if [[ "${toString preferNvme}" == "true" ]] && [[ "$disk_link" =~ nvme- ]]; then
          score=$((score + 10000))
        fi

        # Bonus for SSD (non-rotational)
        if [[ "${toString preferSSD}" == "true" ]]; then
          rotational_file="/sys/block/$(basename "$device")/queue/rotational"
          if [[ -f "$rotational_file" ]] && [[ "$(cat "$rotational_file")" == "0" ]]; then
            score=$((score + 1000))
          fi
        fi

        # Update best disk if this one scores higher
        if [[ $score -gt $best_score ]]; then
          best_score=$score
          best_disk="$device"
        fi
      done

      # Use fallback if no disk found
      if [[ -z "$best_disk" ]]; then
        best_disk="${fallbackDisk}"
      fi

      echo -n "$best_disk" > $out
    '';
  in
    builtins.readFile detectDrv;

  # Detect matching disks for RAID configurations
  detectMatchingDisks = {
    count ? 2,
    sizeTolerancePercent ? 5,
    minSizeGB ? 100,
    preferSameBrand ? true,
    excludeDisks ? [],
  }: let
    detectDrv = pkgs.runCommand "detect-matching-disks" {} ''
      declare -A disk_info
      declare -a suitable_disks

      # Collect information about all suitable disks
      for disk_link in /dev/disk/by-id/*; do
        # Skip partitions
        [[ "$disk_link" =~ -part[0-9]+$ ]] && continue

        # Skip virtual devices
        [[ "$disk_link" =~ (loop|dm-|md) ]] && continue

        device=$(readlink -f "$disk_link")
        [[ -b "$device" ]] || continue

        # Skip excluded disks
        excluded=false
        ${lib.concatMapStrings (disk: ''
          [[ "$device" == "${disk}" ]] && excluded=true
        '')
        excludeDisks}
        [[ "$excluded" == "true" ]] && continue

        # Skip removable
        removable_file="/sys/block/$(basename "$device")/removable"
        if [[ -f "$removable_file" ]] && [[ "$(cat "$removable_file")" == "1" ]]; then
          continue
        fi

        # Get size
        size_bytes=$(blockdev --getsize64 "$device" 2>/dev/null || echo 0)
        size_gb=$((size_bytes / 1073741824))

        # Skip if too small
        [[ $size_gb -lt ${toString minSizeGB} ]] && continue

        # Extract brand from disk link
        brand=$(basename "$disk_link" | sed -E 's/^[^-]*-([^_-]*).*/\1/')

        # Store disk info
        disk_info["$device"]="$size_gb:$brand"
        suitable_disks+=("$device")
      done

      # Group disks by size (within tolerance)
      declare -A size_groups
      for disk in "''${suitable_disks[@]}"; do
        IFS=':' read -r size brand <<< "''${disk_info[$disk]}"

        # Round size to tolerance groups
        tolerance_range=$((size * ${toString sizeTolerancePercent} / 100))
        group_size=$((size / tolerance_range * tolerance_range))

        if [[ -z "''${size_groups[$group_size]}" ]]; then
          size_groups[$group_size]="$disk"
        else
          size_groups[$group_size]="''${size_groups[$group_size]} $disk"
        fi
      done

      # Find the best group with enough disks
      best_group=""
      best_count=0

      for group_size in "''${!size_groups[@]}"; do
        group_disks=(''${size_groups[$group_size]})
        group_count=''${#group_disks[@]}

        if [[ $group_count -ge ${toString count} ]] && [[ $group_count -gt $best_count ]]; then
          best_count=$group_count
          best_group="''${size_groups[$group_size]}"
        fi
      done

      if [[ -n "$best_group" ]]; then
        # Take first N disks from best group
        echo "$best_group" | tr ' ' '\n' | head -${toString count} | tr '\n' ' ' | sed 's/ $//' > $out
      else
        # No suitable group found
        echo "ERROR: Could not find ${toString count} matching disks with size tolerance ${toString sizeTolerancePercent}%" >&2
        echo "" > $out
      fi
    '';
    result = builtins.readFile detectDrv;
  in
    if result == ""
    then throw "Could not find ${toString count} matching disks"
    else lib.splitString " " result;

  # Detect disk by patterns (e.g., specific models or vendors)
  detectDiskByPattern = {
    patterns ? [], # List of regex patterns to match against /dev/disk/by-id/
    preferredPatterns ? [], # Patterns to prefer if multiple matches
    fallback ? null,
    minSizeGB ? 20,
  }: let
    detectDrv = pkgs.runCommand "detect-disk-by-pattern" {} ''
      declare -a all_matches
      declare -a preferred_matches

      for disk_link in /dev/disk/by-id/*; do
        # Skip partitions
        [[ "$disk_link" =~ -part[0-9]+$ ]] && continue

        device=$(readlink -f "$disk_link")
        [[ -b "$device" ]] || continue

        # Check size
        size_bytes=$(blockdev --getsize64 "$device" 2>/dev/null || echo 0)
        size_gb=$((size_bytes / 1073741824))
        [[ $size_gb -lt ${toString minSizeGB} ]] && continue

        # Check against patterns
        ${lib.concatMapStrings (pattern: ''
          if [[ "$disk_link" =~ ${pattern} ]]; then
            all_matches+=("$device")
          fi
        '')
        patterns}

        # Check against preferred patterns
        ${lib.concatMapStrings (pattern: ''
          if [[ "$disk_link" =~ ${pattern} ]]; then
            preferred_matches+=("$device")
          fi
        '')
        preferredPatterns}
      done

      # Return preferred match if available
      if [[ ''${#preferred_matches[@]} -gt 0 ]]; then
        echo -n "''${preferred_matches[0]}" > $out
      elif [[ ''${#all_matches[@]} -gt 0 ]]; then
        echo -n "''${all_matches[0]}" > $out
      elif [[ -n "${toString fallback}" ]]; then
        echo -n "${toString fallback}" > $out
      else
        echo "ERROR: No disk matching patterns: ${toString patterns}" >&2
        echo -n "" > $out
      fi
    '';
    result = builtins.readFile detectDrv;
  in
    if result == ""
    then throw "No disk matching patterns: ${toString patterns}"
    else result;

  # Generate stable hostId from hostname for ZFS
  generateHostId = hostname: let
    hash = builtins.hashString "sha256" hostname;
  in
    builtins.substring 0 8 hash;

  # Detect disk type (NVMe, SATA SSD, HDD, etc.)
  getDiskType = disk: let
    typeDrv = pkgs.runCommand "get-disk-type" {} ''
      device="${disk}"

      # Check if NVMe
      if [[ "$device" =~ nvme ]]; then
        echo "nvme" > $out
        exit 0
      fi

      # Check rotation for SSD vs HDD
      rotational_file="/sys/block/$(basename "$device")/queue/rotational"
      if [[ -f "$rotational_file" ]]; then
        if [[ "$(cat "$rotational_file")" == "0" ]]; then
          echo "ssd" > $out
        else
          echo "hdd" > $out
        fi
      else
        echo "unknown" > $out
      fi
    '';
  in
    builtins.readFile typeDrv;

  # Helper to check if disk exists and is suitable
  validateDisk = disk: {minSizeGB ? 20}: let
    validateDrv = pkgs.runCommand "validate-disk" {} ''
      device="${disk}"

      # Check if device exists
      if [[ ! -b "$device" ]]; then
        echo "false" > $out
        exit 0
      fi

      # Check size
      size_bytes=$(blockdev --getsize64 "$device" 2>/dev/null || echo 0)
      size_gb=$((size_bytes / 1073741824))

      if [[ $size_gb -ge ${toString minSizeGB} ]]; then
        echo "true" > $out
      else
        echo "false" > $out
      fi
    '';
  in
    builtins.readFile validateDrv == "true";

  # Get disk capacity in GB
  getDiskSizeGB = disk: let
    sizeDrv = pkgs.runCommand "get-disk-size" {} ''
      device="${disk}"

      if [[ -b "$device" ]]; then
        size_bytes=$(blockdev --getsize64 "$device" 2>/dev/null || echo 0)
        size_gb=$((size_bytes / 1073741824))
        echo "$size_gb" > $out
      else
        echo "0" > $out
      fi
    '';
  in
    lib.toInt (builtins.readFile sizeDrv);
}
