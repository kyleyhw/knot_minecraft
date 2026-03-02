# Server Settings

## Default settings

| Setting | Value |
|---|---|
| Minecraft version | Latest release (auto-downloaded) |
| RAM allocation | 3 GB |
| Render distance | 16 chunks |
| Simulation distance | 10 chunks |
| Difficulty | Easy |
| Gamemode | Survival |
| Max players | 20 |
| Online mode | true |
| PvP | true |

## How to change settings

### Local hosting

Edit `server/server.properties` directly, then restart the server.

### AWS hosting

SSH into the running instance:

```bash
ssh -i minecraft-server-key.pem ec2-user@<IP>
```

Edit the properties file:

```bash
sudo nano /opt/minecraft/server/server.properties
```

Then reload in the Minecraft console:

```bash
sudo screen -r minecraft
# type: reload
# detach: Ctrl+A, D
```

Note: some settings (like difficulty and gamemode) take effect immediately with `reload`. Others (like render distance) require a full server restart.
