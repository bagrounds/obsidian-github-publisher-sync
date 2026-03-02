#!/usr/bin/env bash
# Build benchmarking script
# Usage: ./scripts/benchmark-build.sh [cold|warm|both]
#
# cold  - Clears OG cache and runs a fresh build
# warm  - Runs build with existing OG cache
# both  - Runs cold then warm (default)

set -euo pipefail
cd "$(dirname "$0")/.."

mode="${1:-both}"

run_build() {
    local label="$1"
    echo "========================================"
    echo "  $label Build"
    echo "========================================"
    rm -rf public
    echo "Starting build at $(date)"
    local start_time
    start_time=$(date +%s)
    npx quartz build 2>&1
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    echo ""
    echo "  => $label build completed in ${duration}s"
    echo ""
}

if [[ "$mode" == "cold" || "$mode" == "both" ]]; then
    rm -rf quartz/.quartz-cache/og-images
    run_build "Cold (no cache)"
fi

if [[ "$mode" == "warm" || "$mode" == "both" ]]; then
    run_build "Warm (cached)"
fi

echo "========================================"
echo "  Build output summary"
echo "========================================"
echo "  OG images: $(find public -name '*-og-image.webp' | wc -l)"
echo "  HTML files: $(find public -name '*.html' | wc -l)"
echo "  Total size: $(du -sh public/ | cut -f1)"
echo "  Cache size: $(du -sh quartz/.quartz-cache/og-images/ 2>/dev/null | cut -f1 || echo 'N/A')"
echo "========================================"
