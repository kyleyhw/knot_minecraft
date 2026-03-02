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

# Check if an instance is already running
if [[ -n "${INSTANCE_ID:-}" ]]; then
    STATE=$(aws ec2 describe-instances \
        --region "$REGION" \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null || echo "terminated")
    if [[ "$STATE" == "running" || "$STATE" == "pending" ]]; then
        echo "Server is already running (instance $INSTANCE_ID, state: $STATE)."
        echo "Use ./status.sh to get the IP, or ./stop.sh to shut it down."
        exit 0
    fi
fi

echo "=== Starting Minecraft Server ==="

# --- Create ephemeral EBS volume if needed ---
if [[ -z "${VOLUME_ID:-}" ]]; then
    echo "Creating 10GB EBS volume in $AZ..."
    VOLUME_ID=$(aws ec2 create-volume \
        --region "$REGION" \
        --availability-zone "$AZ" \
        --size 10 \
        --volume-type gp3 \
        --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=minecraft-world}]" \
        --query 'VolumeId' \
        --output text)
    echo "  Volume: $VOLUME_ID"

    echo "  Waiting for volume to become available..."
    aws ec2 wait volume-available --region "$REGION" --volume-ids "$VOLUME_ID"

    sed -i "s/^VOLUME_ID=.*/VOLUME_ID=$VOLUME_ID/" "$ENV_FILE"
fi

# --- Resolve latest Amazon Linux 2023 AMI ---
echo "Looking up latest Amazon Linux 2023 AMI..."
AMI_ID=$(aws ec2 describe-images \
    --region "$REGION" \
    --owners amazon \
    --filters \
        "Name=name,Values=al2023-ami-2023.*-x86_64" \
        "Name=state,Values=available" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text)
echo "  AMI: $AMI_ID"

# --- User data script (runs on first boot) ---
USERDATA=$(cat <<'BOOT'
#!/bin/bash
set -ex

# Wait for the EBS volume to attach
while [ ! -e /dev/xvdf ]; do sleep 1; done

# Format if new, then mount
if ! blkid /dev/xvdf; then
    mkfs.ext4 /dev/xvdf
fi
mkdir -p /opt/minecraft
mount /dev/xvdf /opt/minecraft

# Install Java 21
if ! java -version 2>&1 | grep -q '"21'; then
    dnf install -y java-21-amazon-corretto-headless
fi

# Install screen
dnf install -y screen

# Download server jar if not present
MC_DIR="/opt/minecraft/server"
mkdir -p "$MC_DIR"
cd "$MC_DIR"

if [ ! -f server.jar ]; then
    # Fetch latest release manifest URL from Mojang
    LATEST_VERSION=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest_v2.json \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['latest']['release'])")
    VERSION_URL=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest_v2.json \
        | python3 -c "import sys,json; vs=json.load(sys.stdin)['versions']; print([v['url'] for v in vs if v['id']=='$LATEST_VERSION'][0])")
    SERVER_URL=$(curl -s "$VERSION_URL" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['downloads']['server']['url'])")
    curl -o server.jar "$SERVER_URL"
fi

# Accept EULA
echo "eula=true" > eula.txt

# Start Minecraft in a screen session
screen -dmS minecraft java -Xmx3G -Xms3G -jar server.jar nogui
BOOT
)

# --- Launch spot instance ---
echo "Requesting spot instance (c7i-flex.large, 4GB RAM)..."
INSTANCE_ID=$(aws ec2 run-instances \
    --region "$REGION" \
    --image-id "$AMI_ID" \
    --instance-type c7i-flex.large \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --placement "AvailabilityZone=$AZ" \
    --instance-market-options 'MarketType=spot,SpotOptions={SpotInstanceType=one-time,InstanceInterruptionBehavior=terminate}' \
    --user-data "$USERDATA" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=minecraft-server}]" \
    --query 'Instances[0].InstanceId' \
    --output text)
echo "  Instance: $INSTANCE_ID"

# Save instance ID
sed -i "s/^INSTANCE_ID=.*/INSTANCE_ID=$INSTANCE_ID/" "$ENV_FILE"

# Wait for instance to be running
echo "  Waiting for instance to start..."
aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"

# --- Attach EBS volume ---
echo "Attaching EBS volume $VOLUME_ID..."
aws ec2 attach-volume \
    --region "$REGION" \
    --volume-id "$VOLUME_ID" \
    --instance-id "$INSTANCE_ID" \
    --device '/dev/xvdf' \
    > /dev/null

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

# --- Auto-restore from backup if available ---
if [[ -f "$BACKUP_FILE" ]]; then
    echo ""
    echo "Backup found — restoring world..."

    SSH_CMD="ssh -i ${REPO_DIR}/${KEY_NAME}.pem $SSH_OPTS ec2-user@$PUBLIC_IP"

    # Wait for SSH to be ready
    echo "  Waiting for SSH..."
    for i in {1..30}; do
        if $SSH_CMD "echo ok" &>/dev/null; then
            break
        fi
        if [[ $i -eq 30 ]]; then
            echo "  WARNING: Timed out waiting for SSH. Server will start without restore."
            echo "  You can manually restore later with: bash infra/restore.sh"
            PUBLIC_IP_DISPLAY="$PUBLIC_IP"
            # Skip restore but continue
            break
        fi
        sleep 5
    done

    # Wait for user data to mount the volume
    echo "  Waiting for volume to mount..."
    for i in {1..30}; do
        if $SSH_CMD "mountpoint -q /opt/minecraft" &>/dev/null; then
            break
        fi
        if [[ $i -eq 30 ]]; then
            echo "  WARNING: Volume not mounted yet. Server may start without restore."
            break
        fi
        sleep 5
    done

    # Stop Minecraft if user data already started it
    $SSH_CMD "sudo screen -S minecraft -p 0 -X stuff 'stop\n'" 2>/dev/null || true
    sleep 5

    # Upload and extract backup
    echo "  Uploading backup..."
    scp -i "${REPO_DIR}/${KEY_NAME}.pem" $SSH_OPTS \
        "$BACKUP_FILE" \
        "ec2-user@$PUBLIC_IP:/tmp/world.tar.gz"

    echo "  Extracting backup..."
    $SSH_CMD "cd /opt/minecraft && sudo rm -rf server/ && sudo tar xzf /tmp/world.tar.gz && sudo rm -f /tmp/world.tar.gz"

    # Restart Minecraft with the restored world
    echo "  Starting Minecraft with restored world..."
    $SSH_CMD "cd /opt/minecraft/server && sudo screen -dmS minecraft java -Xmx3G -Xms3G -jar server.jar nogui"

    echo "  World restored successfully."
fi

echo ""
echo "=== Server launching ==="
echo "Instance:  $INSTANCE_ID"
echo "Public IP: $PUBLIC_IP"
echo "Connect:   $PUBLIC_IP:25565"
echo ""
if [[ -f "$BACKUP_FILE" ]]; then
    echo "World restored from backup — server is ready in ~1 minute."
else
    echo "Fresh server — needs 2-3 minutes to install Java and start Minecraft."
fi
echo "SSH:       ssh -i ${KEY_NAME}.pem ec2-user@$PUBLIC_IP"
echo "Console:   ssh in, then: sudo screen -r minecraft"
