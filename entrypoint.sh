#!/usr/bin/env bash

# ComfyUI Docker Startup File v1.0.2 by John Aldred
# http://www.johnaldred.com
# http://github.com/kaouthia

set -e

# --- Force ComfyUI-Manager config (uv off, no file logging, safe DB) ---
# Make sure user dirs exist and are writable (handles Windows bind mounts)
mkdir -p /app/ComfyUI/user /app/ComfyUI/user/default
chown -R "$(id -u)":"$(id -g)" /app/ComfyUI/user || true
chmod -R u+rwX /app/ComfyUI/user || true

CFG_DIR="/app/ComfyUI/user/default/ComfyUI-Manager"
CFG_FILE="$CFG_DIR/config.ini"
DB_DIR="$CFG_DIR"
DB_PATH="${DB_DIR}/manager.db"
SQLITE_URL="sqlite:////${DB_PATH}"

mkdir -p "$CFG_DIR"

if [ ! -f "$CFG_FILE" ]; then
  echo "↳ Creating ComfyUI-Manager config.ini (uv OFF, no file logging, DB cache)"
  cat > "$CFG_FILE" <<EOF
[default]
use_uv = False
file_logging = False
db_mode = cache
database_url = ${SQLITE_URL}
EOF
else
  echo "↳ Updating ComfyUI-Manager config.ini (uv OFF, no file logging, DB cache)"
  # use_uv = False
  grep -q '^use_uv' "$CFG_FILE" \
    && sed -i 's/^use_uv.*/use_uv = False/' "$CFG_FILE" \
    || printf '\nuse_uv = False\n' >> "$CFG_FILE"

  # file_logging = False (and drop any existing log_path line)
  grep -q '^file_logging' "$CFG_FILE" \
    && sed -i 's/^file_logging.*/file_logging = False/' "$CFG_FILE" \
    || printf '\nfile_logging = False\n' >> "$CFG_FILE"
  sed -i '/^log_path[[:space:]=]/d' "$CFG_FILE" || true

  # db_mode = cache (prevents file DB usage)
  grep -q '^db_mode' "$CFG_FILE" \
    && sed -i 's/^db_mode.*/db_mode = cache/' "$CFG_FILE" \
    || printf '\ndb_mode = cache\n' >> "$CFG_FILE"

  # Provide a safe DB URL anyway (future-proof if Manager flips off cache)
  grep -q '^database_url' "$CFG_FILE" \
    && sed -i "s|^database_url.*|database_url = ${SQLITE_URL}|" "$CFG_FILE" \
    || printf "database_url = ${SQLITE_URL}\n" >> "$CFG_FILE"
fi


# --- Prepare custom nodes ---
CN_DIR=/app/ComfyUI/custom_nodes
INIT_MARKER="$CN_DIR/.custom_nodes_initialized"

declare -A REPOS=(
  ["ComfyUI-Manager"]="https://github.com/ltdrdata/ComfyUI-Manager.git"
  ["ComfyUI_essentials"]="https://github.com/cubiq/ComfyUI_essentials.git"
  ["ComfyUI-Crystools"]="https://github.com/crystian/ComfyUI-Crystools.git"
  ["rgthree-comfy"]="https://github.com/rgthree/rgthree-comfy.git"
  ["ComfyUI-KJNodes"]="https://github.com/kijai/ComfyUI-KJNodes.git"
  ["ComfyUI_UltimateSDUpscale"]="https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git"
  ["ComfyUI-Impact-Pack"]="https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
  ["ComfyUI-Impact-Subpack"]="https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git"
  ["comfyui_controlnet_aux"]="https://github.com/Fannovel16/comfyui_controlnet_aux.git"
)

mkdir -p "$CN_DIR"

# Clone any missing repos (idempotent per-node — handles repos added after first run)
NEW_NODES=()
for name in "${!REPOS[@]}"; do
  url="${REPOS[$name]}"
  target="$CN_DIR/$name"
  if [ -d "$target" ]; then
    echo "  ↳ $name already exists, skipping clone"
  else
    echo "  ↳ Cloning $name"
    git clone --depth 1 "$url" "$target"
    NEW_NODES+=("$name")
  fi
done

# Per-node install markers live in /tmp (container writable layer): they
# survive `docker restart` (fast subsequent boots) but not a container
# rebuild. A rebuild wipes pip's site-packages too — so the markers and
# the actual installs go together, and a fresh container reinstalls
# everything cleanly. The single legacy $INIT_MARKER on the host volume
# is ignored — it persists across rebuilds and used to skip installs even
# when pip packages were gone (e.g. RES4LYF after a rebuild on 2026-05-20).
echo "↳ Checking custom_node dependencies…"
INSTALLED_ANY=0
INSTALL_FAILED=()
for dir in "$CN_DIR"/*/; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  req="$dir/requirements.txt"
  marker="/tmp/.deps.${name}"
  [ -f "$req" ] || continue
  if [ -f "$marker" ]; then
    continue
  fi
  echo "  ↳ Installing $name requirements"
  if python -m pip install --no-cache-dir --break-system-packages --upgrade -r "$req"; then
    touch "$marker"
    INSTALLED_ANY=1
  else
    INSTALL_FAILED+=("$name")
    echo "  ✗ pip install failed for $name — will retry on next start"
  fi
done
if [ $INSTALLED_ANY -eq 0 ] && [ ${#INSTALL_FAILED[@]} -eq 0 ]; then
  echo "↳ All custom_node deps already installed for this container."
fi
if [ ${#INSTALL_FAILED[@]} -gt 0 ]; then
  echo "↳ ⚠ Failed installs: ${INSTALL_FAILED[*]} — container will start anyway, retry on next launch."
fi

echo "↳ Launching ComfyUI"
exec "$@"