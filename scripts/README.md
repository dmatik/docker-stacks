# Minecraft Server Management Scripts

This folder contains utility scripts for managing and maintaining the Minecraft server.

---

## `reset-minecraft-world.sh`

Automates the complete cycle of resetting a Minecraft world from scratch and immediately launching chunk pre-generation with **Chunky**.

### What It Does

1. **Stops the Server**: Gracefully stops the `minecraft-server` Docker container.
2. **Cleans World Data (No Backup)**:
   - Deletes `/data/<world_name>` (Overworld)
   - Deletes `/data/<world_name>_nether` (Nether)
   - Deletes `/data/<world_name>_the_end` (The End)
   - Removes cached tiles for the world from Squaremap (`/data/plugins/squaremap/web/tiles/<world_name>*`)
   - Updates `level-name` in `server.properties`
3. **Restarts the Container**: Starts the container back up so PaperMC can generate a pristine new world.
4. **Waits for Server & RCON Readiness**: Automatically polls the server every 5 seconds until RCON is online and accepting commands (prevents commands from failing while Java boots).
5. **Configures & Starts Chunky**:
   - `chunky world <world_name>` — selects the target world.
   - `chunky spawn` — sets center coordinates to world spawn.
   - `chunky radius <radius>` — sets the pre-generation radius in blocks (defaults to `3000`).
   - `chunky start` — launches chunk pre-generation in the background.

---

## Setup & Configuration

Credentials and server connection details are loaded from `.env`.

1. **Create your `.env` file** from the example template:
   ```bash
   cp scripts/.env.example scripts/.env
   ```

2. **Edit `scripts/.env`** with your credentials:
   ```bash
   # SSH Host / IP address
   HOST=your_server_host_or_ip

   # SSH Username
   USER=your_username

   # SSH Password (leave blank if using SSH key authentication)
   PASSWORD=your_password_here

   # Optional overrides (defaults shown)
   MINECRAFT_CONTAINER_NAME=minecraft-server
   MINECRAFT_DATA_DIR=/home/username/docker/minecraft-server/data
   ```

> [!NOTE]
> `scripts/.env` is ignored by Git and will never be committed to GitHub.

### Prerequisites

- **Mac / Linux Client**:
  - Standard `ssh` client.
  - *(Optional)* `sshpass` if you authenticate using a password instead of SSH keys.
    - macOS (Homebrew): `brew install hudochenkov/sshpass/sshpass`

---

## Usage

Run the script from the root of the repository:

### Basic Example (Default Radius: 3000 blocks)
```bash
./scripts/reset-minecraft-world.sh Trosman
```

### Custom Radius Example
```bash
./scripts/reset-minecraft-world.sh Trosman 5000
```

### Where Can You Run It?
- **From your local machine (Mac/Linux)**: The script detects that it is running remotely and automatically forwards execution to the host over SSH.
- **Directly on the remote server**: If executed on the server itself, it recognizes local storage and runs without an SSH wrapper.

---

## Monitoring & Post-Generation

### Check Chunky Progress
Chunky runs asynchronously inside the container. To check the generation percentage, speed, and ETA:
```bash
# On the server:
docker exec -i minecraft-server rcon-cli chunky progress

# Or in-game (as OP):
/chunky progress
```

### Chunky Controls
- **Pause**: `docker exec -i minecraft-server rcon-cli chunky pause`
- **Continue**: `docker exec -i minecraft-server rcon-cli chunky continue`
- **Cancel**: `docker exec -i minecraft-server rcon-cli chunky cancel`

### Squaremap Full Render
Once Chunky finishes pre-generating chunks, update the Squaremap web viewer (port `8080`):
```bash
docker exec -i minecraft-server rcon-cli squaremap fullrender Trosman
```
