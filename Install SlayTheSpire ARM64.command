#!/bin/bash
# Double-clickable entry point for the Slay the Spire ARM64 patch installer.
cd "$(dirname "$0")" || exit 1
./install.sh
echo
read -r -p "Press Return to close this window..."
