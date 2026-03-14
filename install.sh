#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Build first
./build.sh

# Install binary to /usr/local/bin
echo ""
echo "Installing binary to /usr/local/bin..."
sudo cp shuck /usr/local/bin/shuck
sudo chmod 755 /usr/local/bin/shuck
echo "Installed: /usr/local/bin/shuck"

# Copy workflow to Services
DEST="$HOME/Library/Services/Shuck Text.workflow"
echo ""
echo "Installing workflow..."
rm -rf "$DEST"
cp -R "Shuck Text.workflow" "$DEST"

echo "Installed to: $DEST"
echo ""
echo "Flushing services cache..."
/System/Library/CoreServices/pbs -flush 2>/dev/null || true

echo ""
echo "Done! To use:"
echo "  1. Select files in Finder"
echo "  2. Right-click > Quick Actions > Shuck Text"
echo ""
echo "If 'Shuck Text' doesn't appear:"
echo "  - Open System Settings > Privacy & Security > Extensions > Finder Extensions"
echo "  - Ensure 'Shuck Text' is enabled"
echo "  - Or log out and log back in"
