#!/usr/bin/env bash
set -euo pipefail
export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
BACKUP_FILE="$REPO_DIR/backups/world.tar.gz"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: .env not found. Run setup.sh first."
    exit 1
fi
source "$ENV_FILE"

if [[ ! -f "$BACKUP_FILE" ]]; then
    echo "ERROR: No backup found at backups/world.tar.gz"
    echo "Run 'bash infra/backup.sh' on the original server first."
    exit 1
fi

if [[ -z "${INSTANCE_ID:-}" ]]; then
    echo "ERROR: No instance ID in .env — server isn't running."
    echo "Run 'bash infra/start.sh' first, then run this script."
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

echo "=== Restoring Minecraft World ==="
echo "Server: $PUBLIC_IP"

# Wait for the server to be SSH-ready (user data may still be running)
echo "Waiting for server to be SSH-ready..."
for i in {1..30}; do
    if $SSH_CMD "echo ok" &>/dev/null; then
        break
    fi
    if [[ $i -eq 30 ]]; then
        echo "ERROR: Timed out waiting for SSH access."
        exit 1
    fi
    sleep 5
done

# Stop Minecraft if it's running
echo "Stopping Minecraft..."
$SSH_CMD "sudo screen -S minecraft -p 0 -X stuff 'stop\n'" 2>/dev/null || true
sleep 15

# Upload the backup
echo "Uploading backup..."
scp -i "${REPO_DIR}/${KEY_NAME}.pem" $SSH_OPTS \
    "$BACKUP_FILE" \
    "ec2-user@$PUBLIC_IP:/tmp/world.tar.gz"

# Extract over the existing server directory
echo "Extracting backup..."
$SSH_CMD "cd /opt/minecraft && sudo rm -rf server/ && sudo tar xzf /tmp/world.tar.gz && rm -f /tmp/world.tar.gz"

# Restart Minecraft
echo "Starting Minecraft..."
$SSH_CMD "cd /opt/minecraft/server && sudo screen -dmS minecraft java -Xmx3G -Xms3G -jar server.jar nogui"

echo ""
echo "=== Restore complete ==="
echo "The world has been restored. Connect to $PUBLIC_IP in Minecraft."
