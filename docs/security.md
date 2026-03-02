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

### Example IAM policy

Attach this policy to the `minecraft-server` IAM user:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "EC2Instances",
            "Effect": "Allow",
            "Action": [
                "ec2:RunInstances",
                "ec2:TerminateInstances",
                "ec2:DescribeInstances",
                "ec2:DescribeImages"
            ],
            "Resource": "*"
        },
        {
            "Sid": "EBSVolumes",
            "Effect": "Allow",
            "Action": [
                "ec2:CreateVolume",
                "ec2:DeleteVolume",
                "ec2:AttachVolume",
                "ec2:DetachVolume",
                "ec2:DescribeVolumes"
            ],
            "Resource": "*"
        },
        {
            "Sid": "SecurityGroups",
            "Effect": "Allow",
            "Action": [
                "ec2:CreateSecurityGroup",
                "ec2:DeleteSecurityGroup",
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress",
                "ec2:DescribeSecurityGroups"
            ],
            "Resource": "*"
        },
        {
            "Sid": "KeyPairs",
            "Effect": "Allow",
            "Action": [
                "ec2:CreateKeyPair",
                "ec2:DeleteKeyPair",
                "ec2:DescribeKeyPairs"
            ],
            "Resource": "*"
        },
        {
            "Sid": "SpotAndTags",
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags",
                "iam:CreateServiceLinkedRole"
            ],
            "Resource": "*"
        }
    ]
}
```

### Credential rotation

If you suspect the access key has been exposed, rotate it immediately:

1. Go to **IAM > Users > minecraft-server > Security credentials**
2. Create a new access key
3. Update your local profile: `aws configure --profile minecraft`
4. Delete the old access key in the IAM console

### What to do if compromised

If the credentials are used maliciously:

1. **Delete the access key immediately** in the IAM console (IAM > Users > minecraft-server > Security credentials > Delete)
2. **Check for unauthorized instances** — go to EC2 in every region and terminate anything you don't recognize
3. **Review CloudTrail** — check the event history for unexpected API calls (EC2 launches, security group changes)
4. **Create a new access key** and update your local profile

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
