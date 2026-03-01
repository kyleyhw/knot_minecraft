#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: .env not found. Run setup.sh first."
    exit 1
fi
source "$ENV_FILE"

echo "=== Minecraft Server Status ==="
echo "Region: $REGION"
echo "Volume: $VOLUME_ID"

if [[ -z "${INSTANCE_ID:-}" ]]; then
    echo "Server:  NOT RUNNING (no instance)"
    exit 0
fi

STATE=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null || echo "not found")

PUBLIC_IP=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text 2>/dev/null || echo "N/A")

echo "Instance: $INSTANCE_ID"
echo "State:    $STATE"

if [[ "$STATE" == "running" ]]; then
    echo "IP:       $PUBLIC_IP"
    echo "Connect:  $PUBLIC_IP:25565"
    echo "SSH:      ssh -i ${KEY_NAME}.pem ec2-user@$PUBLIC_IP"
else
    echo ""
    echo "Server is not running. Use ./start.sh to launch it."
fi
