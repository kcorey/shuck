#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

echo "Compiling Shuck.swift..."
swiftc -O -o shuck Shuck.swift

echo "Built: $(pwd)/shuck"
echo "Size: $(du -h shuck | cut -f1)"
