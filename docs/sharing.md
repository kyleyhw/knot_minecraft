# Sharing the Server

## Host locally for friends

The simplest way — no AWS account needed:

1. Clone this repo and run `git lfs pull`
2. Run `bash local-start.sh`
3. Share your IP — friends connect to `<your-ip>:25565`

The server runs in the foreground. Type `stop` or press Ctrl+C to shut down. The world is automatically backed up on exit.

Requires Java 21+.

### Finding your IP

Friends need your IP address to connect. Find it with:

- **Windows:** `ipconfig` — look for "IPv4 Address" under your active adapter
- **macOS:** `ipconfig getifaddr en0` (Wi-Fi) or `en1` (Ethernet)
- **Linux:** `ip addr show` — look for `inet` under your active interface (e.g., `eth0`, `wlan0`)

This gives your **local/LAN IP** (usually `192.168.x.x`). Friends on the same Wi-Fi network can connect directly with this IP.

### Port forwarding (friends outside your network)

For friends on a different network (not your Wi-Fi), you need to forward port **25565** on your router:

1. Open your router's admin page (usually `192.168.1.1` or `192.168.0.1`)
2. Find the port forwarding section (sometimes under "NAT" or "Virtual Server")
3. Forward external port **25565** (TCP) to your local IP on port **25565**
4. Share your **public IP** — find it by searching "what is my IP" in a browser

Friends connect to `<your-public-ip>:25565`.

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

## Conflict handling

If two people try to run `start.sh` at the same time on the same AWS account, the second run will detect the existing instance and exit:

```
Server is already running (instance i-0abc123, state: running).
Use ./status.sh to get the IP, or ./stop.sh to shut it down.
```

Only one server can run at a time per AWS account. The script checks for a running instance before launching a new one.
