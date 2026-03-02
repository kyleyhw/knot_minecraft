# Security

## IAM least-privilege policy

A dedicated IAM user `minecraft-server` should be created with the minimum permissions needed. It can only:

- Launch, describe, and terminate EC2 instances
- Create, describe, attach, detach, and delete EBS volumes
- Manage security groups and key pairs
- Create the EC2 Spot service-linked role
- Create resource tags

It **cannot** access S3, IAM (beyond the spot role), billing, other AWS services, or any resources outside EC2. If the credentials are compromised, the blast radius is limited to EC2 in this account.

The AWS CLI profile `minecraft` is configured locally at `~/.aws/credentials` and referenced automatically by all scripts via `export AWS_PROFILE=minecraft` in the `.env` file.

## Network security

- The security group only opens two ports: **25565** (Minecraft) and **22** (SSH)
- Both are open to `0.0.0.0/0` (the whole internet) — this is necessary so friends on different networks can connect
- SSH access requires the private key (`minecraft-server-key.pem`) which is gitignored
- The Minecraft server runs with `online-mode=true`, meaning only authenticated (paid) Minecraft accounts can connect

## Sensitive files excluded from git

| File | Contents |
|---|---|
| `infra/.env` | AWS resource IDs (security group, volume, instance) |
| `*.pem` | SSH private key |
| `server/` | Extracted local server directory (only the tarball backup is tracked) |

These are listed in `.gitignore` and should never be committed.

## `StrictHostKeyChecking=no` tradeoff

The infra scripts use `-o StrictHostKeyChecking=no` when SSHing into EC2 instances. This disables host key verification, which means the scripts won't reject a man-in-the-middle attack.

This is a deliberate tradeoff: because each spot instance gets a new host key on launch, strict checking would require manual intervention every time. The risk is low — you're connecting to an IP you just provisioned in your own AWS account — but it's worth noting. If this concerns you, you can remove the flag and manually accept the host key after each `start.sh`.
