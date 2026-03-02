#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_DIR="$SCRIPT_DIR/server"
BACKUP_FILE="$SCRIPT_DIR/backups/world.tar.gz"

echo "=== Minecraft Local Server ==="

# --- Check for Java 21+ ---
if ! command -v java &>/dev/null; then
    echo "ERROR: Java not found."
    echo "Install Java 21 or newer:"
    echo "  macOS:   brew install openjdk@21"
    echo "  Ubuntu:  sudo apt install openjdk-21-jre-headless"
    echo "  Windows: https://adoptium.net/temurin/releases/?version=21"
    exit 1
fi

JAVA_VER=$(java -version 2>&1 | head -1 | sed 's/.*"\([0-9]*\).*/\1/')
if [[ "$JAVA_VER" -lt 21 ]]; then
    echo "ERROR: Java 21+ required (found Java $JAVA_VER)."
    echo "Install Java 21 or newer:"
    echo "  macOS:   brew install openjdk@21"
    echo "  Ubuntu:  sudo apt install openjdk-21-jre-headless"
    echo "  Windows: https://adoptium.net/temurin/releases/?version=21"
    exit 1
fi
echo "Java $JAVA_VER detected."

# --- Restore from backup or set up fresh server ---
if [[ -f "$BACKUP_FILE" && ! -d "$SERVER_DIR" ]]; then
    echo "Restoring world from backup..."
    cd "$SCRIPT_DIR"
    tar xzf "$BACKUP_FILE"
    echo "  Restored to server/"
elif [[ ! -d "$SERVER_DIR" ]]; then
    echo "No backup found — downloading fresh Minecraft server..."
    mkdir -p "$SERVER_DIR"
    cd "$SERVER_DIR"

    # Fetch latest server.jar from Mojang
    LATEST_VERSION=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest_v2.json \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['latest']['release'])")
    VERSION_URL=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest_v2.json \
        | python3 -c "import sys,json; vs=json.load(sys.stdin)['versions']; print([v['url'] for v in vs if v['id']=='$LATEST_VERSION'][0])")
    SERVER_URL=$(curl -s "$VERSION_URL" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['downloads']['server']['url'])")
    echo "  Downloading Minecraft $LATEST_VERSION..."
    curl -o server.jar "$SERVER_URL"

    # Accept EULA
    echo "eula=true" > eula.txt
    echo "  Server $LATEST_VERSION ready."
else
    echo "Using existing server directory."
fi

cd "$SERVER_DIR"

echo ""
echo "Starting Minecraft server on localhost:25565"
echo "Type 'stop' in the console or press Ctrl+C to shut down."
echo ""

# --- Run Minecraft in foreground ---
java -Xmx3G -Xms3G -jar server.jar nogui || true

# --- Auto-backup after server exits ---
echo ""
echo "Server stopped. Backing up world..."
mkdir -p "$SCRIPT_DIR/backups"
cd "$SCRIPT_DIR"
tar czf "$BACKUP_FILE" server/

BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
echo "Backup saved: backups/world.tar.gz ($BACKUP_SIZE)"
echo ""
echo "To save your world to git:"
echo "  git add backups/ && git commit -m 'Update world backup' && git push"
