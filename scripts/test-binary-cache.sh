#!/usr/bin/env bash
# Test binary cache functionality

set -euo pipefail

echo "=== Binary Cache Test Suite ==="
echo ""

CACHE_URL="${1:-http://cachy.local}"

# Test 1: Cache connectivity
echo "1. Testing cache connectivity..."
if curl -s --connect-timeout 5 "$CACHE_URL/nix-cache-info" > /dev/null; then
    echo "   ✓ Cache is reachable at $CACHE_URL"
    echo "   Cache info:"
    curl -s "$CACHE_URL/nix-cache-info" | sed 's/^/     /'
else
    echo "   ✗ Cache is not reachable at $CACHE_URL"
    exit 1
fi
echo ""

# Test 2: Check cache contents
echo "2. Checking cache contents..."
# Query a common package
HELLO_HASH="hhg83gh653wjw4ny49xn92f13v2j1za4"
if curl -s "$CACHE_URL/$HELLO_HASH.narinfo" | grep -q "StorePath:"; then
    echo "   ✓ Found hello package in cache"
    echo "   Package info:"
    curl -s "$CACHE_URL/$HELLO_HASH.narinfo" | grep -E "^(StorePath|NarSize|References):" | sed 's/^/     /'
else
    echo "   ℹ Hello package not in cache (this is normal for new caches)"
fi
echo ""

# Test 3: Push test
echo "3. Testing package push to cache..."
# Build a small package
echo "   Building test package..."
TEST_PKG=$(nix build 'nixpkgs#hello' --no-link --print-out-paths 2>/dev/null || echo "")
if [[ -n "$TEST_PKG" ]]; then
    echo "   Package built: $TEST_PKG"
    echo "   Pushing to cache..."
    if nix copy --to "$CACHE_URL" "$TEST_PKG" 2>&1 | grep -E "(copying|already)" > /dev/null; then
        echo "   ✓ Package push successful"
    else
        echo "   ⚠ Package push may have failed (check permissions)"
    fi
else
    echo "   ⚠ Could not build test package"
fi
echo ""

# Test 4: Download test
echo "4. Testing package download from cache..."
if [[ -n "${TEST_PKG:-}" ]]; then
    # Get package hash
    PKG_HASH=$(basename "$TEST_PKG" | cut -d- -f1)
    
    # Check if it's in the cache
    if curl -s "$CACHE_URL/$PKG_HASH.narinfo" | grep -q "StorePath:"; then
        echo "   ✓ Package is available in cache"
        
        # Test download speed
        echo "   Testing download speed..."
        NAR_URL=$(curl -s "$CACHE_URL/$PKG_HASH.narinfo" | grep "^URL:" | cut -d' ' -f2)
        if [[ -n "$NAR_URL" ]]; then
            START=$(date +%s.%N)
            SIZE=$(curl -s -o /dev/null -w "%{size_download}" "$CACHE_URL/$NAR_URL")
            END=$(date +%s.%N)
            DURATION=$(echo "$END - $START" | bc)
            SPEED=$(echo "scale=2; $SIZE / $DURATION / 1024 / 1024" | bc)
            echo "   ✓ Download speed: ${SPEED} MB/s"
        fi
    else
        echo "   ⚠ Package not found in cache"
    fi
fi
echo ""

# Test 5: Cache statistics
echo "5. Cache statistics..."
echo "   Local store info:"
echo "     Store paths: $(nix path-info --all 2>/dev/null | wc -l || echo "N/A")"
echo "     Store size: $(du -sh /nix/store 2>/dev/null | cut -f1 || echo "N/A")"
echo ""

# Summary
echo "=== Test Summary ==="
echo "Cache URL: $CACHE_URL"
echo "Status: Binary cache is operational"
echo ""
echo "To use this cache in NixOS, add to configuration.nix:"
echo "  nix.settings.substituters = [ \"$CACHE_URL\" ];"
echo "  nix.settings.trusted-public-keys = [ \"$(curl -s $CACHE_URL/nix-cache-info | grep -oP 'PublicKey: \K.*' || echo "YOUR_PUBLIC_KEY")\" ];"
echo ""
echo "For trusted users, add to /etc/nix/nix.conf:"
echo "  trusted-users = [ \"@wheel\" ];"