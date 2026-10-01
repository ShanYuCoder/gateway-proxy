# shellcheck shell=bash
# Shared loader for docker/routes.json (requires python3 + docker/lib/routes-emit.py).

routes_json_init() {
  local script_dir="${1:?}"
  ROUTES_JSON="${script_dir}/routes.json"
  ROUTES_EMIT="${script_dir}/lib/routes-emit.py"
  if [[ ! -f "$ROUTES_JSON" ]]; then
    echo "[ERROR] Missing $ROUTES_JSON — cp routes.json.example routes.json" >&2
    return 1
  fi
  if [[ ! -x "$ROUTES_EMIT" ]] && [[ ! -f "$ROUTES_EMIT" ]]; then
    echo "[ERROR] Missing $ROUTES_EMIT" >&2
    return 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "[ERROR] python3 required to read routes.json" >&2
    return 1
  fi
}

routes_json_records() {
  python3 "$ROUTES_EMIT" records "$ROUTES_JSON"
}

routes_json_hostlines() {
  python3 "$ROUTES_EMIT" hostlines "$ROUTES_JSON"
}

routes_json_domains() {
  python3 "$ROUTES_EMIT" domains "$ROUTES_JSON"
}
