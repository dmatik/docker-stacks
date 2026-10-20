#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: reset-minecraft-world.sh
# Purpose: Stop Minecraft server, cleanly delete world without backup,
#          start the container, wait for server readiness, and launch Chunky pre-gen.
# Usage:   ./scripts/reset-minecraft-world.sh <world_name> [radius]
# Example: ./scripts/reset-minecraft-world.sh Trosman 3000
#
# Credentials & configuration are loaded from .env (see scripts/.env.example)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ------------------------------------------------------------------------------
# 1. Load .env configuration
# ------------------------------------------------------------------------------
if [ -f "${SCRIPT_DIR}/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/.env"
    set +a
elif [ -f "${REPO_DIR}/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "${REPO_DIR}/.env"
    set +a
fi

HOST="${HOST:-}"
USER="${USER:-}"
PASSWORD="${PASSWORD:-}"
CONTAINER_NAME="${MINECRAFT_CONTAINER_NAME:-minecraft-server}"
DATA_DIR="${MINECRAFT_DATA_DIR:-/home/${USER:-docker}/docker/minecraft-server/data}"

# ------------------------------------------------------------------------------
# 2. Validate arguments
# ------------------------------------------------------------------------------
if [ $# -lt 1 ] || [ -z "$1" ]; then
    echo "Error: Missing world name (LEVEL)."
    echo "Usage:   $0 <world_name> [radius]"
    echo "Example: $0 Trosman 3000"
    exit 1
fi

LEVEL="$1"
RADIUS="${2:-3000}"

# ------------------------------------------------------------------------------
# 3. Remote execution via SSH (if not running locally on the server)
# ------------------------------------------------------------------------------
if [ ! -d "$DATA_DIR" ]; then
    if [ -z "$HOST" ]; then
        echo "Error: HOST is not set."
        echo "Please configure HOST in scripts/.env (see scripts/.env.example)."
        exit 1
    fi

    # Build SSH target (e.g., user@host or host)
    if [ -n "$USER" ]; then
        SSH_TARGET="${USER}@${HOST}"
    else
        SSH_TARGET="${HOST}"
    fi

    echo "=> Local data directory not detected."
    echo "=> Connecting to remote host (${SSH_TARGET}) via SSH..."

    # Configure SSH command (with sshpass if password is provided)
    SSH_CMD=(ssh)
    if [ -n "$PASSWORD" ]; then
        if command -v sshpass >/dev/null 2>&1; then
            export SSHPASS="$PASSWORD"
            SSH_CMD=(sshpass -e ssh -o StrictHostKeyChecking=accept-new)
        else
            echo "Warning: PASSWORD is set, but 'sshpass' is not installed in PATH."
            echo "Falling back to standard SSH (key-based or interactive password prompt)..."
        fi
    fi

    "${SSH_CMD[@]}" -T "$SSH_TARGET" "bash -s" -- "$LEVEL" "$RADIUS" "$CONTAINER_NAME" "$DATA_DIR" << 'REMOTE_EOF'
#!/usr/bin/env bash
set -euo pipefail

LEVEL="$1"
RADIUS="$2"
CONTAINER_NAME="$3"
DATA_DIR="$4"

echo "=========================================="
echo " Resetting Minecraft World: $LEVEL"
echo " Chunky Radius:             $RADIUS blocks"
echo " Container:                 $CONTAINER_NAME"
echo " Data Directory:            $DATA_DIR"
echo "=========================================="

# 1. Stop container
echo "==> [1/5] Stopping container: $CONTAINER_NAME..."
docker stop "$CONTAINER_NAME"

# 2. Clean world files (no backup)
echo "==> [2/5] Deleting world files for '$LEVEL' in $DATA_DIR..."
rm -rf "${DATA_DIR:?}/${LEVEL}"
rm -rf "${DATA_DIR:?}/${LEVEL}_nether"
rm -rf "${DATA_DIR:?}/${LEVEL}_the_end"
rm -rf "${DATA_DIR}/plugins/squaremap/web/tiles/${LEVEL}"* 2>/dev/null || true

# Update level-name in server.properties if present
if [ -f "$DATA_DIR/server.properties" ]; then
    sed -i "s/^level-name=.*/level-name=${LEVEL}/" "$DATA_DIR/server.properties"
fi

# 3. Start container
echo "==> [3/5] Starting container: $CONTAINER_NAME..."
docker start "$CONTAINER_NAME"

# 4. Wait for server and RCON to become ready
echo "==> [4/5] Waiting for Minecraft server and RCON to initialize..."
MAX_ATTEMPTS=40
ATTEMPT=0
READY=false

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if docker exec -i "$CONTAINER_NAME" rcon-cli help >/dev/null 2>&1; then
        READY=true
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    echo "    Still loading... (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    sleep 5
done

if [ "$READY" != true ]; then
    echo "Error: Minecraft server / RCON did not become ready in time."
    exit 1
fi

echo "    Minecraft server is UP and RCON is ready!"

# 5. Chunky configuration and start
echo "==> [5/5] Configuring and starting Chunky pre-generation..."
docker exec -i "$CONTAINER_NAME" rcon-cli chunky world "$LEVEL"
docker exec -i "$CONTAINER_NAME" rcon-cli chunky spawn
docker exec -i "$CONTAINER_NAME" rcon-cli chunky radius "$RADIUS"
docker exec -i "$CONTAINER_NAME" rcon-cli chunky start

echo "=========================================="
echo " Chunky has started successfully!"
echo " World:  $LEVEL"
echo " Radius: $RADIUS"
echo ""
echo " Check progress anytime with:"
echo "   docker exec -i $CONTAINER_NAME rcon-cli chunky progress"
echo "=========================================="
REMOTE_EOF
    exit $?
fi

# ------------------------------------------------------------------------------
# 4. Direct execution (when running locally on the server)
# ------------------------------------------------------------------------------
echo "=========================================="
echo " Resetting Minecraft World: $LEVEL"
echo " Chunky Radius:             $RADIUS blocks"
echo " Container:                 $CONTAINER_NAME"
echo " Data Directory:            $DATA_DIR"
echo "=========================================="

# 1. Stop container
echo "==> [1/5] Stopping container: $CONTAINER_NAME..."
docker stop "$CONTAINER_NAME"

# 2. Clean world files (no backup)
echo "==> [2/5] Deleting world files for '$LEVEL' in $DATA_DIR..."
rm -rf "${DATA_DIR:?}/${LEVEL}"
rm -rf "${DATA_DIR:?}/${LEVEL}_nether"
rm -rf "${DATA_DIR:?}/${LEVEL}_the_end"
rm -rf "${DATA_DIR}/plugins/squaremap/web/tiles/${LEVEL}"* 2>/dev/null || true

# Update level-name in server.properties if present
if [ -f "$DATA_DIR/server.properties" ]; then
    sed -i "s/^level-name=.*/level-name=${LEVEL}/" "$DATA_DIR/server.properties"
fi

# 3. Start container
echo "==> [3/5] Starting container: $CONTAINER_NAME..."
docker start "$CONTAINER_NAME"

# 4. Wait for server and RCON to become ready
echo "==> [4/5] Waiting for Minecraft server and RCON to initialize..."
MAX_ATTEMPTS=40
ATTEMPT=0
READY=false

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if docker exec -i "$CONTAINER_NAME" rcon-cli help >/dev/null 2>&1; then
        READY=true
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    echo "    Still loading... (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    sleep 5
done

if [ "$READY" != true ]; then
    echo "Error: Minecraft server / RCON did not become ready in time."
    exit 1
fi

echo "    Minecraft server is UP and RCON is ready!"

# 5. Chunky configuration and start
echo "==> [5/5] Configuring and starting Chunky pre-generation..."
docker exec -i "$CONTAINER_NAME" rcon-cli chunky world "$LEVEL"
docker exec -i "$CONTAINER_NAME" rcon-cli chunky spawn
docker exec -i "$CONTAINER_NAME" rcon-cli chunky radius "$RADIUS"
docker exec -i "$CONTAINER_NAME" rcon-cli chunky start

echo "=========================================="
echo " Chunky has started successfully!"
echo " World:  $LEVEL"
echo " Radius: $RADIUS"
echo ""
echo " Check progress anytime with:"
echo "   docker exec -i $CONTAINER_NAME rcon-cli chunky progress"
echo "=========================================="
