#!/usr/bin/env bash
set -euo pipefail
export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
BACKUP_DIR="$REPO_DIR/backups"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: .env not found. Run setup.sh first."
    exit 1
fi
source "$ENV_FILE"

if [[ -z "${INSTANCE_ID:-}" ]]; then
    echo "ERROR: No instance ID in .env — server isn't running."
    exit 1
fi

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

if [[ -z "$PUBLIC_IP" || "$PUBLIC_IP" == "None" ]]; then
    echo "ERROR: Could not determine server IP. Is the instance running?"
    exit 1
fi

SSH_CMD="ssh -i ${REPO_DIR}/${KEY_NAME}.pem $SSH_OPTS ec2-user@$PUBLIC_IP"

echo "=== Backing Up Minecraft World ==="
echo "Server: $PUBLIC_IP"

# Stop Minecraft so the world is in a consistent state
echo "Stopping Minecraft for a consistent backup..."
$SSH_CMD "sudo screen -S minecraft -p 0 -X stuff 'stop\n'" 2>/dev/null || true
echo "Waiting 15s for world save..."
sleep 15

# Create tarball on the server
echo "Creating tarball on server..."
$SSH_CMD "cd /opt/minecraft && sudo tar czf /tmp/world.tar.gz server/"

# Download the tarball
mkdir -p "$BACKUP_DIR"
echo "Downloading backup..."
scp -i "${REPO_DIR}/${KEY_NAME}.pem" $SSH_OPTS \
    "ec2-user@$PUBLIC_IP:/tmp/world.tar.gz" \
    "$BACKUP_DIR/world.tar.gz"

# Clean up remote tarball
$SSH_CMD "sudo rm -f /tmp/world.tar.gz"

# Restart Minecraft
echo "Restarting Minecraft..."
$SSH_CMD "cd /opt/minecraft/server && sudo screen -dmS minecraft java -Xmx3G -Xms3G -jar server.jar nogui"

BACKUP_SIZE=$(du -h "$BACKUP_DIR/world.tar.gz" | cut -f1)
echo ""
echo "=== Backup complete ==="
echo "File: backups/world.tar.gz ($BACKUP_SIZE)"
echo ""
echo "To commit the backup to git:"
echo "  git add backups/"
echo "  git commit -m 'Update world backup'"
echo "  git push"
