# Server Settings

## Default `server.properties`

The server generates `server.properties` on first run. Below are the defaults, grouped by category.

### Network

```properties
server-port=25565           # TCP port players connect to
server-ip=                  # leave blank to bind all interfaces
online-mode=true            # require authenticated Minecraft accounts
network-compression-threshold=256
```

### Gameplay

```properties
gamemode=survival           # survival, creative, adventure, spectator
difficulty=easy             # peaceful, easy, normal, hard
pvp=true                    # players can damage each other
allow-flight=false          # kick players who fly in survival
spawn-protection=16         # radius around spawn only OPs can build in
max-players=20
force-gamemode=false        # force default gamemode on join
hardcore=false              # one life — world deletes on death
allow-nether=true
```

### World

```properties
level-name=world
level-seed=                 # leave blank for random seed
level-type=minecraft\:normal  # normal, flat, large_biomes, amplified
generate-structures=true    # villages, temples, etc.
max-world-size=29999984     # world border radius in blocks
spawn-animals=true
spawn-monsters=true
spawn-npcs=true
```

### Performance

```properties
view-distance=16            # render distance in chunks (default 10, we use 16)
simulation-distance=10      # tick distance in chunks
max-tick-time=60000         # ms before watchdog kills the server
entity-broadcast-range-percentage=100
```

### Server

```properties
motd=A Minecraft Server     # message shown in server browser
enable-command-block=false
enable-query=false
enable-rcon=false
enable-status=true
white-list=false
enforce-whitelist=false
```

### Memory

The server launches with 3 GB of RAM:

```
java -Xmx3G -Xms3G -jar server.jar nogui
```

To change this, edit the `java` command in `local-start.sh` (local) or in the user-data section of `infra/start.sh` (AWS).

## How to change settings

### Local hosting

1. Start the server once so it generates `server/server.properties`
2. Stop the server
3. Edit `server/server.properties`
4. Start the server again

Changes to most settings (difficulty, gamemode, max-players) take effect on restart. Some can be changed live — see the operators section below.

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

Settings changed on AWS are included in the backup — they persist across sessions.

## Operators (OPs)

Operators are players with elevated permissions. They can:

- Change gamemode (`/gamemode creative <player>`)
- Give items (`/give <player> diamond 64`)
- Kick and ban players (`/kick <player>`, `/ban <player>`)
- Teleport (`/tp <player> <target>`)
- Change time and weather (`/time set day`, `/weather clear`)
- Set difficulty and other game rules live

### How to OP a player

From the server console, run:

```
/op <player>
```

**Accessing the console:**
- **Local:** type directly in the terminal where the server is running
- **AWS:** SSH in, then attach to the screen session:
  ```bash
  ssh -i minecraft-server-key.pem ec2-user@<IP>
  sudo screen -r minecraft
  ```
  Detach with `Ctrl+A, D` (don't Ctrl+C — that kills the server).

### Permission levels

The `ops.json` file in the server directory stores operators with permission levels:

| Level | Permissions |
|---|---|
| 1 | Bypass spawn protection |
| 2 | Use `/clear`, `/difficulty`, `/effect`, `/gamemode`, `/give`, `/tp`, etc. |
| 3 | Use `/ban`, `/kick`, `/op`, `/deop` |
| 4 | Use `/stop`, `/save-all`, access all commands |

By default, `/op` grants level 4. You can edit `ops.json` directly to set a specific level.

### How to deop a player

```
/deop <player>
```

This removes the player from `ops.json`.

## Whitelist

A whitelist restricts the server to approved players only.

### Enable the whitelist

1. Set `white-list=true` in `server.properties` (or run `/whitelist on` in the console)
2. Add players:
   ```
   /whitelist add <player>
   ```
3. Remove players:
   ```
   /whitelist remove <player>
   ```

The whitelist is stored in `whitelist.json` in the server directory.
