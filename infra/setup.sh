#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="$(cd "$(dirname "$0")" && pwd)/.env"
REGION="eu-west-2"
AZ="${REGION}a"
KEY_NAME="minecraft-server-key"
SG_NAME="minecraft-server-sg"

if [[ -f "$ENV_FILE" ]]; then
    echo "ERROR: .env already exists at $ENV_FILE"
    echo "If you want to start fresh, run teardown.sh first."
    exit 1
fi

echo "=== Minecraft Server — One-Time AWS Setup ==="
echo "Region: $REGION (London)"
echo ""

# --- Key Pair ---
echo "Creating key pair '$KEY_NAME'..."
aws ec2 create-key-pair \
    --region "$REGION" \
    --key-name "$KEY_NAME" \
    --query 'KeyMaterial' \
    --output text > "${KEY_NAME}.pem"
chmod 400 "${KEY_NAME}.pem"
echo "  Saved private key to ${KEY_NAME}.pem"

# --- Security Group ---
echo "Creating security group '$SG_NAME'..."
SG_ID=$(aws ec2 create-security-group \
    --region "$REGION" \
    --group-name "$SG_NAME" \
    --description "Minecraft server - TCP 25565 and SSH" \
    --query 'GroupId' \
    --output text)

aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --ip-permissions \
        "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=0.0.0.0/0,Description=SSH}]" \
        "IpProtocol=tcp,FromPort=25565,ToPort=25565,IpRanges=[{CidrIp=0.0.0.0/0,Description=Minecraft}]" \
    > /dev/null
echo "  Security group: $SG_ID"

# --- Save resource IDs ---
cat > "$ENV_FILE" <<EOF
export AWS_PROFILE=minecraft
REGION=$REGION
AZ=$AZ
KEY_NAME=$KEY_NAME
SG_ID=$SG_ID
VOLUME_ID=
INSTANCE_ID=
EOF

echo ""
echo "=== Setup complete ==="
echo "Resource IDs saved to .env"
echo ""
echo "Next: run ./start.sh to launch the server."
