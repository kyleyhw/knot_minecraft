#!/usr/bin/env bash
set -euo pipefail
export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

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
        echo "Cleared instance ID from .env."
    fi
    exit 0
fi

PUBLIC_IP=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

echo "=== Stopping Minecraft Server ==="

# --- Graceful Minecraft shutdown via SSH ---
echo "Sending 'stop' command to Minecraft..."
ssh -i "${SCRIPT_DIR}/${KEY_NAME}.pem" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    "ec2-user@$PUBLIC_IP" \
    "sudo screen -S minecraft -p 0 -X stuff 'stop\n'" 2>/dev/null || true

echo "Waiting 30s for world save..."
sleep 30

# --- Detach EBS volume ---
echo "Detaching EBS volume $VOLUME_ID..."
# Unmount first via SSH (best-effort)
ssh -i "${SCRIPT_DIR}/${KEY_NAME}.pem" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    "ec2-user@$PUBLIC_IP" \
    "sudo umount /opt/minecraft" 2>/dev/null || true

aws ec2 detach-volume \
    --region "$REGION" \
    --volume-id "$VOLUME_ID" \
    --instance-id "$INSTANCE_ID" \
    > /dev/null
echo "  Waiting for volume to detach..."
aws ec2 wait volume-available --region "$REGION" --volume-ids "$VOLUME_ID"

# --- Terminate instance ---
echo "Terminating instance $INSTANCE_ID..."
aws ec2 terminate-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    > /dev/null
aws ec2 wait instance-terminated --region "$REGION" --instance-ids "$INSTANCE_ID"

# Clear instance ID
sed -i "s/^INSTANCE_ID=.*/INSTANCE_ID=/" "$ENV_FILE"

echo ""
echo "=== Server stopped and instance terminated ==="
echo "Your world is safe on EBS volume $VOLUME_ID."
echo "Run ./start.sh to play again."
