#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_DIR="$SCRIPT_DIR/server"
BACKUP_FILE="$SCRIPT_DIR/backups/world.tar.gz"
ARCHIVE_DIR="$SCRIPT_DIR/backups/archive"

echo "=== Minecraft World Reset ==="
echo ""
echo "This will DELETE the current world and server directory."
echo "The existing backup will be archived locally before deletion."
echo ""
read -rp "Are you sure? Type 'yes' to proceed: " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted."
    exit 0
fi

# --- Archive existing backup ---
if [[ -f "$BACKUP_FILE" ]]; then
    mkdir -p "$ARCHIVE_DIR"
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    ARCHIVE_FILE="$ARCHIVE_DIR/world-$TIMESTAMP.tar.gz"
    echo "Archiving backup to $ARCHIVE_FILE..."
    mv "$BACKUP_FILE" "$ARCHIVE_FILE"
    ARCHIVE_SIZE=$(du -h "$ARCHIVE_FILE" | cut -f1)
    echo "  Archived ($ARCHIVE_SIZE)"
else
    echo "No backup to archive."
fi

# --- Delete server directory ---
if [[ -d "$SERVER_DIR" ]]; then
    echo "Removing server/..."
    rm -rf "$SERVER_DIR"
    echo "  Removed."
else
    echo "No server directory to remove."
fi

echo ""
echo "World reset complete."
echo ""
echo "To commit the reset:"
echo "  git add backups/ && git commit -m 'Reset world' && git push"
