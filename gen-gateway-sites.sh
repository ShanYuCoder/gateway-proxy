#!/usr/bin/env bash
# Sinh nginx gateway conf từ routes.json + copy infra từ gateway/sites.example/.
#
# Cert nginx (từ .env PROJECT_NAME + SSL_DOMAIN_BASE, lib/ssl-cert-names.sh):
#   /etc/nginx/certs/<basename>.crt + .key   (vd. dev.local.com.crt)
#
# Biến gen-sites: khai báo trong .env (xem .env.example). Script chỉ gán default nếu biến chưa set sau source .env.
#
# Usage: bash gen-gateway-sites.sh [path/to/.env] [path/to/sites-dir]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
ENV_FILE="${1:-$PROJECT_ROOT/.env}"
SITES_DIR="${2:-$PROJECT_ROOT/gateway/sites}"

# shellcheck source=lib/routes-json.sh
source "$SCRIPT_DIR/lib/routes-json.sh"
routes_json_init "$SCRIPT_DIR" || exit 1

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[ERROR] Missing env file: $ENV_FILE (cp .env.example .env)" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

# shellcheck source=lib/ssl-cert-names.sh
source "$SCRIPT_DIR/lib/ssl-cert-names.sh"
ssl_cert_load_paths

API_CONTAINER_PORT="${API_CONTAINER_PORT:-80}"
PORTAL_CONTAINER_PORT="${PORTAL_CONTAINER_PORT:-3000}"
GATEWAY_CONTAINER="${GATEWAY_CONTAINER:-${PROJECT_NAME:-local_dev}_gateway_nginx}"
domain_to_conf() {
  printf '%s' "$1" | sed 's/[^a-zA-Z0-9._-]/_/g'
}

mkdir -p "$SITES_DIR"
if [[ ! -w "$SITES_DIR" ]]; then
  echo "[ERROR] $SITES_DIR not writable (thường do docker compose up trước gen-sites/init-sites)." >&2
  echo "  Fix (sudo): sudo chown -R \$(id -u):\$(id -g) $SITES_DIR" >&2
  echo "  Fix (docker): docker run --rm -v $SITES_DIR:/sites alpine chown -R \$(id -u):\$(id -g) /sites" >&2
  exit 1
fi

# Infra (phpmyadmin, pgadmin, redisadmin, mail, mock, stackport) — không sinh từ routes.json.
# Copy template từ gateway/sites.example/ nếu file chưa có (không ghi đè chỉnh tay).
SITES_EXAMPLE_DIR="$PROJECT_ROOT/gateway/sites.example"
copy_sites_example() {
  [[ -d "$SITES_EXAMPLE_DIR" ]] || return 0
  local f base
  for f in "$SITES_EXAMPLE_DIR"/*.conf; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    if [[ ! -f "$SITES_DIR/$base" ]]; then
      sed "s/__SSL_CERT_BASENAME__/${SSL_CERT_BASENAME}/g" "$f" >"$SITES_DIR/$base"
      echo "[INFO] Copied infra template $base (from sites.example)"
    fi
  done
}
copy_sites_example

write_api_conf() {
  local api_dom=$1 stack_slug=$2 internal_h=$3
  local api_port="${4:-$API_CONTAINER_PORT}"
  local api_upstream api_note
  api_upstream="http://${stack_slug}-api-nginx:${api_port}"
  api_note="${stack_slug}-api-nginx:${api_port} (Docker network)"
  local f="$SITES_DIR/$(domain_to_conf "$api_dom").conf"
  local existed=0
  [[ -f "$f" ]] && existed=1
  cat >"$f" <<EOF
# API ${api_dom} → ${api_note} (proxy Host: ${internal_h})
server {
    listen 80;
    server_name ${api_dom};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name ${api_dom};
    ssl_certificate ${SSL_CERT_FILE};
    ssl_certificate_key ${SSL_CERT_KEY};
    ssl_protocols TLSv1.2 TLSv1.3;
    resolver 127.0.0.11 valid=10s ipv6=off;

    # PHPUnit HTML report — relative redirect keeps the browser on saas-api.local.com.
    location = /coverage/ {
        return 301 /coverage;
    }

    location = /coverage {
        set \$api_upstream ${api_upstream};
        proxy_http_version 1.1;
        proxy_pass \$api_upstream;
        proxy_set_header Host ${internal_h};
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
        proxy_pass_header Set-Cookie;
        proxy_pass_header Vary;
    }

    location ^~ /coverage/ {
        set \$api_upstream ${api_upstream};
        proxy_http_version 1.1;
        proxy_pass \$api_upstream;
        proxy_set_header Host ${internal_h};
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
        proxy_pass_header Set-Cookie;
        proxy_pass_header Vary;
    }

    location / {
        set \$api_upstream ${api_upstream};
        proxy_http_version 1.1;
        proxy_pass \$api_upstream;
        proxy_set_header Host ${internal_h};
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
        proxy_pass_header Set-Cookie;
        proxy_pass_header Vary;
    }
}
EOF
  if [[ "$existed" -eq 1 ]]; then
    echo "[INFO] Overwrote $f"
  else
    echo "[INFO] Created $f"
  fi
}

write_portal_conf() {
  local portal_dom=$1 stack_slug=$2
  local portal_port="${3:-$PORTAL_CONTAINER_PORT}"
  local f="$SITES_DIR/$(domain_to_conf "$portal_dom").conf"
  local existed=0
  local portal_target="http://${stack_slug}-portal-node:${portal_port}"
  local portal_note="${stack_slug}-portal-node:${portal_port} (Docker network)"
  [[ -f "$f" ]] && existed=1
  cat >"$f" <<EOF
# Portal ${portal_dom} → ${portal_note}
server {
    listen 80;
    server_name ${portal_dom};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name ${portal_dom};
    ssl_certificate ${SSL_CERT_FILE};
    ssl_certificate_key ${SSL_CERT_KEY};
    ssl_protocols TLSv1.2 TLSv1.3;
    resolver 127.0.0.11 valid=10s ipv6=off;
    location / {
        set \$portal_upstream ${portal_target};
        proxy_pass \$portal_upstream;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF
  if [[ "$existed" -eq 1 ]]; then
    echo "[INFO] Overwrote $f"
  else
    echo "[INFO] Created $f"
  fi
}

write_web_fastcgi_conf() {
  local web_dom=$1 fcgi_host=$2 docroot=$3
  local f="$SITES_DIR/$(domain_to_conf "$web_dom").conf"
  local existed=0
  [[ -f "$f" ]] && existed=1
  cat >"$f" <<EOF
# External PHP ${web_dom} → fastcgi ${fcgi_host}:9000 root=${docroot}
server {
    listen 80;
    server_name ${web_dom};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name ${web_dom};
    ssl_certificate ${SSL_CERT_FILE};
    ssl_certificate_key ${SSL_CERT_KEY};
    ssl_protocols TLSv1.2 TLSv1.3;
    root ${docroot};
    index index.php index.html;
    client_max_body_size 40M;
    resolver 127.0.0.11 valid=10s ipv6=off;

    location ^~ /storage/ {
        try_files \$uri =404;
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \\.php\$ {
        try_files \$uri =404;
        set \$fcgi_upstream ${fcgi_host}:9000;
        fastcgi_pass \$fcgi_upstream;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTPS on;
    }
}
EOF
  if [[ "$existed" -eq 1 ]]; then
    echo "[INFO] Overwrote $f (fastcgi)"
  else
    echo "[INFO] Created $f (fastcgi)"
  fi
}

write_web_http_proxy_conf() {
  local web_dom=$1 web_upstream=$2 proxy_host=$3
  local f="$SITES_DIR/$(domain_to_conf "$web_dom").conf"
  local existed=0
  [[ -f "$f" ]] && existed=1
  cat >"$f" <<EOF
# External HTTP ${web_dom} → ${web_upstream} (proxy Host: ${proxy_host})
server {
    listen 80;
    server_name ${web_dom};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name ${web_dom};
    ssl_certificate ${SSL_CERT_FILE};
    ssl_certificate_key ${SSL_CERT_KEY};
    ssl_protocols TLSv1.2 TLSv1.3;
    resolver 127.0.0.11 valid=10s ipv6=off;
    location / {
        set \$web_upstream ${web_upstream};
        proxy_http_version 1.1;
        proxy_pass \$web_upstream;
        proxy_set_header Host ${proxy_host};
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass_header Set-Cookie;
        proxy_pass_header Vary;
    }
}
EOF
  if [[ "$existed" -eq 1 ]]; then
    echo "[INFO] Overwrote $f (http proxy)"
  else
    echo "[INFO] Created $f (http proxy)"
  fi
}


write_external_node_conf() {
  local node_dom=$1 node_port=$2 node_container=$3
  if [[ -z "$node_container" ]]; then
    echo "[ERROR] $node_dom (role=node): thiếu container trong routes.json sites[]" >&2
    exit 1
  fi
  local f="$SITES_DIR/$(domain_to_conf "$node_dom").conf"
  local existed=0
  local node_target="http://${node_container}:${node_port}"
  local node_note="${node_container}:${node_port} (Docker network)"
  [[ -f "$f" ]] && existed=1
  cat >"$f" <<EOF
# External Nuxt ${node_dom} → ${node_note}
server {
    listen 80;
    server_name ${node_dom};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name ${node_dom};
    ssl_certificate ${SSL_CERT_FILE};
    ssl_certificate_key ${SSL_CERT_KEY};
    ssl_protocols TLSv1.2 TLSv1.3;
    resolver 127.0.0.11 valid=10s ipv6=off;
    location / {
        set \$node_upstream ${node_target};
        proxy_pass \$node_upstream;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF
  if [[ "$existed" -eq 1 ]]; then
    echo "[INFO] Overwrote $f"
  else
    echo "[INFO] Created $f"
  fi
}

used=0
while IFS=$'\t' read -r proj role host port col5 col6 col7 || [[ -n "${proj:-}" ]]; do
  [[ -z "${proj:-}" ]] && continue
  [[ "$port" == "-" ]] && port=""
  [[ "$col5" == "-" ]] && col5=""
  [[ "$col6" == "-" ]] && col6=""
  [[ "$col7" == "-" ]] && col7=""
  case "$role" in
    api)
      stack_slug="$col5"
      internal_h="$col6"
      [[ -z "$stack_slug" ]] && stack_slug="$proj"
      internal_h="${internal_h:-$host}"
      write_api_conf "$host" "$stack_slug" "$internal_h" "${port:-$API_CONTAINER_PORT}"
      ((used++)) || true
      ;;
    portal)
      stack_slug="$col5"
      [[ -z "$stack_slug" ]] && stack_slug="$proj"
      write_portal_conf "$host" "$stack_slug" "${port:-$PORTAL_CONTAINER_PORT}"
      ((used++)) || true
      ;;
    web)
      if [[ -n "$col5" && -n "$col6" ]]; then
        write_web_fastcgi_conf "$host" "$col5" "$col6"
      elif [[ -n "$col7" ]]; then
        write_web_http_proxy_conf "$host" "$col7" "$host"
      else
        echo "[ERROR] $host (role=web): cần container+docroot (fastcgi) hoặc proxy trong routes.json" >&2
        exit 1
      fi
      ((used++)) || true
      ;;
    node)
      if [[ -z "$port" ]]; then
        echo "[ERROR] $host (role=node): thiếu port trong routes.json" >&2
        exit 1
      fi
      write_external_node_conf "$host" "$port" "$col5"
      ((used++)) || true
      ;;
    *)
      echo "[ERROR] Unknown route role: $role (project $proj)" >&2
      exit 1
      ;;
  esac
done < <(routes_json_records)

if [[ "$used" -eq 0 ]]; then
  echo "[ERROR] No routes in $ROUTES_JSON — thêm ít nhất một project" >&2
  exit 1
fi

# Cập nhật đường dẫn cert trong mọi conf (placeholder / tên cũ → ${SSL_CERT_BASENAME}.crt).
for f in "$SITES_DIR"/*.conf; do
  [[ -f "$f" ]] || continue
  ssl_cert_substitute_in_file "$f"
done

echo "[DONE] Gateway sites in: $SITES_DIR/ (from $ROUTES_JSON)"

bash "$SCRIPT_DIR/gen-gateway-network-aliases.sh" "$ENV_FILE"

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$GATEWAY_CONTAINER"; then
  if docker exec "$GATEWAY_CONTAINER" nginx -t >/dev/null 2>&1; then
    docker exec "$GATEWAY_CONTAINER" nginx -s reload
    echo "[INFO] Reloaded gateway nginx ($GATEWAY_CONTAINER)"
  else
    echo "[WARN] Gateway config test failed — reload skipped" >&2
  fi
else
  echo "[INFO] Gateway not running ($GATEWAY_CONTAINER) — start stack then: docker exec $GATEWAY_CONTAINER nginx -s reload"
fi
