# Sharing the Server

## Host locally for friends

The simplest way — no AWS account needed:

1. Clone this repo and run `git lfs pull`
2. Run `bash local-start.sh`
3. Share your IP — friends connect to `<your-ip>:25565`

The server runs in the foreground. Type `stop` or press Ctrl+C to shut down. The world is automatically backed up on exit.

Requires Java 21+.

## Host on another AWS account

Anyone can host on their own AWS account with the same world:

1. Set up their own AWS account with a `minecraft-server` IAM user (see [security.md](security.md#iam-least-privilege-policy))
2. Configure the `minecraft` AWS CLI profile: `aws configure --profile minecraft`
3. Clone this repo and run `git lfs pull`
4. Run `bash infra/setup.sh` then `bash infra/start.sh`

The world is automatically restored from the backup — same world, different account.

## Share start/stop access on the same AWS account

If you want friends to be able to start and stop the server on your AWS account:

1. Give them the AWS access key and secret key for the `minecraft-server` IAM user
2. They run `aws configure --profile minecraft` and enter the credentials
3. They clone this repo and copy the `infra/.env` file (it's gitignored, so share it directly)
4. They can then run `bash infra/start.sh` and `bash infra/stop.sh`

The IAM user has least-privilege permissions — they can only manage the Minecraft EC2 resources.
