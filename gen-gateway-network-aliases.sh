#!/usr/bin/env bash
# Sinh network aliases cho gateway-nginx trên base_shared_net từ docker/routes.json.
# Container trên cùng mạng resolve https://<host>.local.com → IP gateway (không cần URL Docker trong .env app).
#
# Usage: bash gen-gateway-network-aliases.sh [path/to/.env]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$SCRIPT_DIR/docker-compose.yml}"
BEGIN_MARKER="# BEGIN gateway-aliases (generated — make gen-sites)"
END_MARKER="# END gateway-aliases"

# shellcheck source=lib/routes-json.sh
source "$SCRIPT_DIR/lib/routes-json.sh"
routes_json_init "$SCRIPT_DIR" || exit 1

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "[ERROR] Missing $COMPOSE_FILE" >&2
  exit 1
fi

if ! grep -qF "$BEGIN_MARKER" "$COMPOSE_FILE"; then
  echo "[ERROR] Markers not found in $COMPOSE_FILE — add gateway-aliases block under gateway-nginx networks.base-shared" >&2
  exit 1
fi

mapfile -t domains < <(routes_json_domains | sort -u)
if [[ ${#domains[@]} -eq 0 ]]; then
  echo "[ERROR] No domains in routes.json" >&2
  exit 1
fi

tmp="$(mktemp)"
{
  echo "        aliases:"
  echo "          $BEGIN_MARKER"
  for d in "${domains[@]}"; do
    echo "          - $d"
  done
  echo "          $END_MARKER"
} >"$tmp"

# Replace aliases block (from "aliases:" through END marker line inclusive).
awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v block_file="$tmp" '
  $0 ~ /^[[:space:]]*aliases:[[:space:]]*$/ && !done {
    while ((getline line < block_file) > 0) print line
    close(block_file)
    skip = 1
    done = 1
    next
  }
  skip && $0 ~ end { skip = 0; next }
  skip { next }
  { print }
' "$COMPOSE_FILE" >"${COMPOSE_FILE}.new"
mv "${COMPOSE_FILE}.new" "$COMPOSE_FILE"

echo "[DONE] Gateway network aliases (${#domains[@]} hosts) in $COMPOSE_FILE"
echo "[INFO] Recreate gateway để áp alias: docker compose -f $COMPOSE_FILE up -d --force-recreate gateway-nginx"
