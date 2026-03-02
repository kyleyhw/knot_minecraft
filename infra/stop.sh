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
    echo "No instance ID in .env — server isn't running."
    exit 0
fi

# Verify instance exists and is running
STATE=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null || echo "terminated")

if [[ "$STATE" != "running" ]]; then
    echo "Instance $INSTANCE_ID is not running (state: $STATE)."
    if [[ "$STATE" == "terminated" || "$STATE" == "shutting-down" ]]; then
        sed -i "s/^INSTANCE_ID=.*/INSTANCE_ID=/" "$ENV_FILE"
        sed -i "s/^VOLUME_ID=.*/VOLUME_ID=/" "$ENV_FILE"
        echo "Cleared instance and volume IDs from .env."
    fi
    exit 0
fi

PUBLIC_IP=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

SSH_CMD="ssh -i ${SCRIPT_DIR}/${KEY_NAME}.pem $SSH_OPTS ec2-user@$PUBLIC_IP"

echo "=== Stopping Minecraft Server ==="

# --- Graceful Minecraft shutdown via SSH ---
echo "Sending 'stop' command to Minecraft..."
$SSH_CMD "sudo screen -S minecraft -p 0 -X stuff 'stop\n'" 2>/dev/null || true

echo "Waiting 30s for world save..."
sleep 30

# --- Backup world before tearing down ---
echo "Backing up world..."
$SSH_CMD "cd /opt/minecraft && sudo tar czf /tmp/world.tar.gz server/"

mkdir -p "$BACKUP_DIR"
scp -i "${SCRIPT_DIR}/${KEY_NAME}.pem" $SSH_OPTS \
    "ec2-user@$PUBLIC_IP:/tmp/world.tar.gz" \
    "$BACKUP_DIR/world.tar.gz"

BACKUP_SIZE=$(du -h "$BACKUP_DIR/world.tar.gz" | cut -f1)
echo "  Backup saved: backups/world.tar.gz ($BACKUP_SIZE)"

# --- Unmount and detach EBS volume ---
if [[ -n "${VOLUME_ID:-}" ]]; then
    echo "Unmounting and detaching EBS volume $VOLUME_ID..."
    $SSH_CMD "sudo umount /opt/minecraft" 2>/dev/null || true

    aws ec2 detach-volume \
        --region "$REGION" \
        --volume-id "$VOLUME_ID" \
        --instance-id "$INSTANCE_ID" \
        > /dev/null
    echo "  Waiting for volume to detach..."
    aws ec2 wait volume-available --region "$REGION" --volume-ids "$VOLUME_ID"

    # --- Delete EBS volume (world is in the backup now) ---
    echo "Deleting EBS volume $VOLUME_ID (world is backed up)..."
    aws ec2 delete-volume \
        --region "$REGION" \
        --volume-id "$VOLUME_ID"
fi

# --- Terminate instance ---
echo "Terminating instance $INSTANCE_ID..."
aws ec2 terminate-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    > /dev/null
aws ec2 wait instance-terminated --region "$REGION" --instance-ids "$INSTANCE_ID"

# Clear instance and volume IDs
sed -i "s/^INSTANCE_ID=.*/INSTANCE_ID=/" "$ENV_FILE"
sed -i "s/^VOLUME_ID=.*/VOLUME_ID=/" "$ENV_FILE"

echo ""
echo "=== Server stopped and instance terminated ==="
echo "World backed up to backups/world.tar.gz"
echo "EBS volume deleted — \$0 idle cost."
echo ""
echo "To save your world to git:"
echo "  git add backups/ && git commit -m 'Update world backup' && git push"
