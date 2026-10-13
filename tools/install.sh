#!/usr/bin/env bash
# Copies the addon into a WoW AddOns folder.
# Usage: tools/install.sh "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns"
set -euo pipefail
dest="${1:?Usage: tools/install.sh <path to Interface/AddOns>}"
dest="${dest%/}"
case "$dest" in
  */AddOns) ;;
  *) echo "Refusing: $dest is not an AddOns folder" >&2; exit 1 ;;
esac
[ -d "$dest" ] || { echo "No such folder: $dest" >&2; exit 1; }
cd "$(dirname "$0")/.."
rsync -a --delete --exclude '.DS_Store' TankTrails/ "$dest/TankTrails/"
echo "Installed TankTrails to $dest/TankTrails"
