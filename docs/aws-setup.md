# AWS Hosting Guide

Complete guide to hosting the Minecraft server on AWS.

## Prerequisites

1. **AWS CLI** — [Install the AWS CLI](https://aws.amazon.com/cli/)
2. **IAM user** — Create a `minecraft-server` IAM user with the permissions listed in [security.md](security.md#iam-least-privilege-policy). Create an access key for this user.
3. **AWS CLI profile** — Configure a `minecraft` profile:

```bash
aws configure --profile minecraft
# Enter the access key ID and secret access key for the minecraft-server IAM user
# Region: eu-west-2
# Output format: json
```

## One-time setup

```bash
bash infra/setup.sh
```

This creates:
- An EC2 key pair (`minecraft-server-key`) — the private key is saved to `minecraft-server-key.pem`
- A security group allowing TCP 25565 (Minecraft) and TCP 22 (SSH)
- An `infra/.env` file with resource IDs

No EBS volume is created — `start.sh` handles that on demand.

## Start the server

```bash
bash infra/start.sh
```

What happens:
1. Creates a 10 GB EBS volume (gp3)
2. Launches a spot instance (c7i-flex.large)
3. Attaches the EBS volume and installs Java 21
4. Restores the world from `backups/world.tar.gz` (if present)
5. Starts Minecraft in a `screen` session

The public IP is printed at the end — share it with friends. They connect in Minecraft via **Multiplayer > Add Server**.

## Stop the server

```bash
bash infra/stop.sh
```

What happens:
1. Sends `stop` to the Minecraft console
2. Waits 30 seconds for the world to save
3. Downloads the world backup via SCP
4. Deletes the EBS volume
5. Terminates the instance

**Always use this instead of terminating the instance manually** — otherwise the world won't be backed up.

After stopping, commit the backup:

```bash
git add backups/ && git commit -m "Update world backup" && git push
```

## Check server status

```bash
bash infra/status.sh
```

Shows the instance state, public IP, and connection info.

## Backup and restore (manual)

While the server is running, you can back up or restore manually:

```bash
bash infra/backup.sh     # download world from running server
bash infra/restore.sh    # upload world to running server
```

`backup.sh` briefly stops Minecraft to get a consistent snapshot, then restarts it. `restore.sh` stops Minecraft, uploads and extracts the backup, then restarts.

## SSH access

```bash
ssh -i minecraft-server-key.pem ec2-user@<IP>
```

To access the Minecraft console:

```bash
sudo screen -r minecraft
```

Detach from the console with `Ctrl+A, D` (do **not** close the terminal or use Ctrl+C — that kills the server).

## Tear down everything

```bash
bash infra/teardown.sh
```

**Permanently deletes** the security group, key pair, and any running instance/volume. Prompts for confirmation.

After teardown, you can run `setup.sh` again to start fresh.
