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

INTERNAL_DEFAULT="${INTERNAL_API_HOST:-laravel.api.com}"
API_CONTAINER_PORT="${API_CONTAINER_PORT:-80}"
PORTAL_CONTAINER_PORT="${PORTAL_CONTAINER_PORT:-3000}"
EXTERNAL_NODE_CONTAINER="${EXTERNAL_NODE_CONTAINER:-${PROJECT_NAME:-local_dev}_frontend_node}"
EXTERNAL_GATEWAY_PROXY="${EXTERNAL_GATEWAY_PROXY:-container}"
EXTERNAL_NGINX_CONTAINER="${EXTERNAL_NGINX_CONTAINER:-${PROJECT_NAME:-local_dev}_nginx}"
EXTERNAL_PHP82_CONTAINER="${EXTERNAL_PHP82_CONTAINER:-${PROJECT_NAME:-local_dev}_php_82}"
EXTERNAL_PHP83_CONTAINER="${EXTERNAL_PHP83_CONTAINER:-${PROJECT_NAME:-local_dev}_php_83}"
EXTERNAL_PHP82_PORT="${EXTERNAL_PHP82_PORT:-18081}"
EXTERNAL_PHP83_PORT="${EXTERNAL_PHP83_PORT:-18082}"
EXTERNAL_PHP82_SCENARIO_PORT="${EXTERNAL_PHP82_SCENARIO_PORT:-18084}"
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

# Map host-published port (routes.json) → external-nginx listen port inside Docker.
external_nginx_listen_port() {
  case "$1" in
    "$EXTERNAL_PHP82_PORT") echo 8081 ;;
    "$EXTERNAL_PHP83_PORT") echo 8082 ;;
    "$EXTERNAL_PHP82_SCENARIO_PORT") echo 8084 ;;
    *) echo "" ;;
  esac
}

resolve_external_web_upstream() {
  local web_port=$1
  local listen
  listen="$(external_nginx_listen_port "$web_port")"
  if [[ "$EXTERNAL_GATEWAY_PROXY" == "container" && -n "$listen" ]]; then
    echo "http://${EXTERNAL_NGINX_CONTAINER}:${listen}"
    return
  fi
  echo "http://host.docker.internal:${web_port}"
}

# routes.json web port → FastCGI upstream + document root (paths khớp mount gateway + php-fpm).
resolve_mairy_fastcgi() {
  local web_port=$1
  case "$web_port" in
    "$EXTERNAL_PHP82_PORT")
      echo "${EXTERNAL_PHP82_CONTAINER}|/var/www/mairy-fullsco/public"
      ;;
    "$EXTERNAL_PHP83_PORT")
      echo "${EXTERNAL_PHP83_CONTAINER}|/var/www/mairy-backend/public"
      ;;
    "$EXTERNAL_PHP82_SCENARIO_PORT")
      echo "${EXTERNAL_PHP82_CONTAINER}|/var/www/mairy-scenario/src/public"
      ;;
    *)
      echo ""
      ;;
  esac
}

write_web_fastcgi_conf() {
  local web_dom=$1 web_port=$2
  local pair fcgi_host docroot
  pair="$(resolve_mairy_fastcgi "$web_port")"
  if [[ -z "$pair" ]]; then
    echo "[ERROR] fastcgi: unknown web port $web_port for $web_dom (routes.json vs EXTERNAL_PHP*_PORT)" >&2
    exit 1
  fi
  fcgi_host="${pair%%|*}"
  docroot="${pair#*|}"
  local f="$SITES_DIR/$(domain_to_conf "$web_dom").conf"
  local existed=0
  [[ -f "$f" ]] && existed=1
  cat >"$f" <<EOF
# Web ${web_dom} → fastcgi ${fcgi_host}:9000 root=${docroot} (EXTERNAL_GATEWAY_PROXY=fastcgi)
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

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \\.php\$ {
        try_files \$uri =404;
        fastcgi_pass ${fcgi_host}:9000;
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

write_web_conf() {
  local web_dom=$1 web_port=$2 proxy_host=$3
  if [[ "$EXTERNAL_GATEWAY_PROXY" == "fastcgi" ]]; then
    write_web_fastcgi_conf "$web_dom" "$web_port"
    return
  fi
  local web_upstream
  web_upstream="$(resolve_external_web_upstream "$web_port")"
  local f="$SITES_DIR/$(domain_to_conf "$web_dom").conf"
  local existed=0
  [[ -f "$f" ]] && existed=1
  cat >"$f" <<EOF
# Web ${web_dom} → ${web_upstream} (proxy Host: ${proxy_host}; EXTERNAL_GATEWAY_PROXY=${EXTERNAL_GATEWAY_PROXY})
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
    echo "[INFO] Overwrote $f"
  else
    echo "[INFO] Created $f"
  fi
}


write_webbeds_app_conf() {
  local app_dom=$1 node_port=$2 php_container=$3 node_container=$4 docroot=$5
  if [[ -z "$php_container" || "$php_container" == "-" ]]; then
    echo "[ERROR] webbeds $app_dom: thiếu phpContainer trong routes.json (project webbeds)" >&2
    exit 1
  fi
  if [[ -z "$node_container" || "$node_container" == "-" ]]; then
    echo "[ERROR] webbeds $app_dom: thiếu nodeContainer trong routes.json" >&2
    exit 1
  fi
  if [[ -z "$docroot" || "$docroot" == "-" ]]; then
    docroot="/var/www/html/public"
  fi
  local f="$SITES_DIR/$(domain_to_conf "$app_dom").conf"
  local existed=0
  [[ -f "$f" ]] && existed=1
  cat >"$f" <<EOF
# Webbeds ${app_dom} → Vue ${node_container}:${node_port} + API fastcgi ${php_container}:9000
server {
    listen 80;
    server_name ${app_dom};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name ${app_dom};
    ssl_certificate ${SSL_CERT_FILE};
    ssl_certificate_key ${SSL_CERT_KEY};
    ssl_protocols TLSv1.2 TLSv1.3;
    client_max_body_size 40M;

    location ^~ /storage/ {
        root ${docroot};
        try_files \$uri =404;
    }

    location ^~ /api {
        root ${docroot};
        try_files \$uri \$uri/ @webbeds_php;
    }

    location @webbeds_php {
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME ${docroot}/index.php;
        fastcgi_param QUERY_STRING \$query_string;
        fastcgi_param HTTPS on;
        fastcgi_pass ${php_container}:9000;
    }

    location / {
        resolver 127.0.0.11 valid=10s ipv6=off;
        set \$node_upstream http://${node_container}:${node_port};
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
    echo "[INFO] Overwrote $f (webbeds app)"
  else
    echo "[INFO] Created $f (webbeds app)"
  fi
}

write_external_node_conf() {
  local node_dom=$1 node_port=$2
  local f="$SITES_DIR/$(domain_to_conf "$node_dom").conf"
  local existed=0
  local node_target="http://${EXTERNAL_NODE_CONTAINER}:${node_port}"
  local node_note="${EXTERNAL_NODE_CONTAINER}:${node_port} (Docker network)"
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
while IFS=$'\t' read -r proj role host port stack_slug internal_h php_container node_container docroot \
  || [[ -n "${proj:-}" ]]; do
  [[ -z "${proj:-}" ]] && continue
  [[ "$port" == "-" ]] && port=""
  [[ "$stack_slug" == "-" ]] && stack_slug=""
  [[ "$internal_h" == "-" ]] && internal_h=""
  [[ "$php_container" == "-" ]] && php_container=""
  [[ "$node_container" == "-" ]] && node_container=""
  [[ "$docroot" == "-" ]] && docroot=""
  case "$role" in
    api)
      [[ -z "$stack_slug" ]] && stack_slug="$proj"
      internal_h="${internal_h:-$INTERNAL_DEFAULT}"
      write_api_conf "$host" "$stack_slug" "$internal_h" "${port:-$API_CONTAINER_PORT}"
      ((used++)) || true
      ;;
    portal)
      [[ -z "$stack_slug" ]] && stack_slug="$proj"
      write_portal_conf "$host" "$stack_slug" "${port:-$PORTAL_CONTAINER_PORT}"
      ((used++)) || true
      ;;
    web)
      write_web_conf "$host" "$port" "$host"
      ((used++)) || true
      ;;
    node)
      write_external_node_conf "$host" "$port"
      ((used++)) || true
      ;;
    app)
      write_webbeds_app_conf "$host" "$port" "$php_container" "$node_container" "$docroot"
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
