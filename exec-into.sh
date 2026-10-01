#!/usr/bin/env bash
# Exec vào container gateway stack — dùng bởi: make exec SVC=<alias> [CMD='...']
#
#   make exec SVC=gateway
#   make exec mysql
#   make exec-list

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "$ENV_FILE"
  set +a
fi

usage() {
  cat <<'EOF'
Usage:
  make exec SVC=<alias>              — shell tương tác
  make exec SVC=<alias> CMD='...'    — chạy một lệnh rồi thoát
  make exec <alias>                  — cùng ý (vd. make exec gateway)
  make exec-list                     — liệt kê alias

Alias:
  gateway, gw          — gateway-nginx
  mysql, mysql-84      — MySQL 8.4
  mysql80, mysql-80    — MySQL 8.0
  redis                — Redis
  redis-commander, redisadmin — Redis Commander UI
  localstack           — LocalStack
  stackport            — StackPort (S3/SQS/SNS UI)
  mailpit, mail        — Mailpit
  mock-api, mock       — mock SMS/Slack
EOF
}

list_aliases() {
  cat <<'EOF'
Alias           Service       Shell
-----           -------       -----
gateway, gw     gateway-nginx sh
mysql           mysql         sh
mysql80         mysql-80      bash
redis           redis         sh
redis-commander redis-commander sh
localstack      localstack    bash
stackport       stackport     sh
mailpit, mail   mailpit       sh
mock-api, mock  mock-api      sh
EOF
}

normalize_alias() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr '_' '-'
}

resolve_target() {
  local alias
  alias="$(normalize_alias "$1")"

  COMPOSE_DIR="$SCRIPT_DIR"
  COMPOSE_FILES=(-f docker-compose.yml)
  SERVICE=""
  WORKDIR=""
  SHELL_CMD="bash"
  USE_TTY=1

  case "$alias" in
    gateway|gw|gateway-nginx)
      SERVICE=gateway-nginx
      SHELL_CMD="sh"
      ;;
    mysql|mysql-84)
      SERVICE=mysql
      SHELL_CMD="sh"
      ;;
    mysql80|mysql-80|mysql8)
      COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.services.yml)
      SERVICE=mysql-80
      SHELL_CMD="bash"
      ;;
    redis)
      COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.services.yml)
      SERVICE=redis
      SHELL_CMD="sh"
      ;;
    redis-commander|redisadmin|redis-admin)
      COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.services.yml)
      SERVICE=redis-commander
      SHELL_CMD="sh"
      ;;
    localstack)
      COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.services.yml)
      SERVICE=localstack
      SHELL_CMD="bash"
      ;;
    stackport)
      COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.services.yml)
      SERVICE=stackport
      SHELL_CMD="sh"
      ;;
    mailpit|mail)
      COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.services.yml)
      SERVICE=mailpit
      SHELL_CMD="sh"
      ;;
    mock-api|mock)
      COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.services.yml)
      SERVICE=mock-api
      SHELL_CMD="sh"
      ;;
    *)
      echo "[ERROR] Unknown alias: $1" >&2
      echo "Run: make exec-list" >&2
      return 1
      ;;
  esac
}

run_exec() {
  local alias="$1"
  shift || true
  local custom_cmd="${CMD:-}"

  resolve_target "$alias" || return 1

  local -a dc
  dc=(docker compose)
  for f in "${COMPOSE_FILES[@]}"; do
    dc+=("$f")
  done

  if ! (cd "$COMPOSE_DIR" && "${dc[@]}" ps --status running --services 2>/dev/null | grep -qx "$SERVICE"); then
    echo "[ERROR] Service '$SERVICE' is not running." >&2
    echo "  cd $COMPOSE_DIR && ${dc[*]} ps -a" >&2
    return 1
  fi

  local -a exec_args
  exec_args=(exec)
  if [[ -n "$WORKDIR" ]]; then
    exec_args+=(-w "$WORKDIR")
  fi
  if [[ -t 0 && -t 1 && "$USE_TTY" == 1 && -z "$custom_cmd" && $# -eq 0 ]]; then
    exec_args+=(-it)
  fi
  exec_args+=("$SERVICE")

  if [[ -n "$custom_cmd" ]]; then
    exec_args+=(sh -lc "$custom_cmd")
  elif [[ $# -gt 0 ]]; then
    exec_args+=("$@")
  else
    exec_args+=("$SHELL_CMD")
  fi

  echo "[exec] ${dc[*]} → $SERVICE${WORKDIR:+ ($WORKDIR)}"
  cd "$COMPOSE_DIR"
  "${dc[@]}" "${exec_args[@]}"
}

main() {
  if [[ "${1:-}" == "--list" || "${1:-}" == "-l" ]]; then
    list_aliases
    exit 0
  fi
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" || -z "${1:-}" ]]; then
    usage
    exit 0
  fi

  local alias="$1"
  shift
  run_exec "$alias" "$@"
}

main "$@"
