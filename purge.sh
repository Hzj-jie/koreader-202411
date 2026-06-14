#!/bin/bash
# Purge everything not coming from origin/master, with self-preservation.
set -euo pipefail

# 1. Self-preservation copy to temp space
TEMP_BACKUP="/tmp/purge.sh"
cp "$0" "$TEMP_BACKUP"

# Ensure the backup gets cleaned up from /tmp on exit
trap 'rm -f "$TEMP_BACKUP"' EXIT

echo "Resetting tracked files to origin/master..."
git reset --hard origin/master

echo "Running standard clean.sh..."
if [ -f "./clean.sh" ]; then
  # This might delete this script file itself
  ./clean.sh || true
fi

echo "Purging all other untracked and ignored files..."
# Use git ls-files --others to get all untracked and ignored files.
# We filter out purge.sh itself in case it's still there, and handle empty results safely.
git ls-files --others -z | { grep -zv "purge.sh" || true; } | xargs -0 rm -rf

echo "Cleaning up empty directories..."
find . -empty -type d -delete 2>/dev/null || true

echo "Restoring purge.sh..."
cp "$TEMP_BACKUP" "$0"
chmod +x "$0"

echo "Workspace successfully purged!"
