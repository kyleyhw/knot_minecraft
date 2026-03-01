#!/usr/bin/env bash
set -euo pipefail
export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "Nothing to tear down — no .env file found."
    exit 0
fi
source "$ENV_FILE"

echo "=== Minecraft Server — Teardown ==="
echo ""
echo "This will PERMANENTLY destroy:"
echo "  - EBS volume $VOLUME_ID (YOUR WORLD DATA)"
echo "  - Security group $SG_ID"
echo "  - Key pair $KEY_NAME"
if [[ -n "${INSTANCE_ID:-}" ]]; then
    echo "  - Instance $INSTANCE_ID (will be terminated)"
fi
echo ""
read -r -p "Type 'yes' to confirm destruction: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted."
    exit 1
fi

echo ""

# --- Terminate instance if running ---
if [[ -n "${INSTANCE_ID:-}" ]]; then
    STATE=$(aws ec2 describe-instances \
        --region "$REGION" \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null || echo "terminated")
    if [[ "$STATE" != "terminated" ]]; then
        echo "Terminating instance $INSTANCE_ID..."
        aws ec2 terminate-instances \
            --region "$REGION" \
            --instance-ids "$INSTANCE_ID" > /dev/null
        aws ec2 wait instance-terminated --region "$REGION" --instance-ids "$INSTANCE_ID"
    fi
fi

# --- Delete EBS volume ---
# Detach first if still attached
VOL_STATE=$(aws ec2 describe-volumes \
    --region "$REGION" \
    --volume-ids "$VOLUME_ID" \
    --query 'Volumes[0].State' \
    --output text 2>/dev/null || echo "not-found")
if [[ "$VOL_STATE" == "in-use" ]]; then
    echo "Detaching volume..."
    aws ec2 detach-volume --region "$REGION" --volume-id "$VOLUME_ID" --force > /dev/null
    aws ec2 wait volume-available --region "$REGION" --volume-ids "$VOLUME_ID"
fi
if [[ "$VOL_STATE" != "not-found" ]]; then
    echo "Deleting EBS volume $VOLUME_ID..."
    aws ec2 delete-volume --region "$REGION" --volume-id "$VOLUME_ID"
fi

# --- Delete security group ---
echo "Deleting security group $SG_ID..."
aws ec2 delete-security-group --region "$REGION" --group-id "$SG_ID" 2>/dev/null || true

# --- Delete key pair and local PEM ---
echo "Deleting key pair $KEY_NAME..."
aws ec2 delete-key-pair --region "$REGION" --key-name "$KEY_NAME" 2>/dev/null || true
rm -f "${SCRIPT_DIR}/${KEY_NAME}.pem"

# --- Clean up .env ---
rm -f "$ENV_FILE"

echo ""
echo "=== All resources destroyed ==="
