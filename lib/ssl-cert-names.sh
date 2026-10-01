#!/usr/bin/env bash
# Tên file cert TLS local từ .env:
#   SSL_CERT_BASENAME = ${PROJECT_NAME}.${SSL_DOMAIN_BASE}  → dev.local.com
#   nginx: /etc/nginx/certs/dev.local.com.crt (+ .key)
# Source sau khi đã load PROJECT_NAME, SSL_DOMAIN_BASE.

ssl_cert_basename() {
  local p="${PROJECT_NAME:-local_dev}"
  local d="${SSL_DOMAIN_BASE:-local.com}"
  d="${d#.}"
  printf '%s.%s' "$p" "$d" | sed 's/[^a-zA-Z0-9._-]/_/g'
}

ssl_cert_load_paths() {
  SSL_CERT_BASENAME="$(ssl_cert_basename)"
  SSL_CERT_FILE="/etc/nginx/certs/${SSL_CERT_BASENAME}.crt"
  SSL_CERT_KEY="/etc/nginx/certs/${SSL_CERT_BASENAME}.key"
  export SSL_CERT_BASENAME SSL_CERT_FILE SSL_CERT_KEY
}

# Thay placeholder hoặc tên cert cũ trong nginx conf.
ssl_cert_substitute_in_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  sed -i \
    -e "s|/etc/nginx/certs/dev-server\\.fullchain\\.crt|${SSL_CERT_FILE}|g" \
    -e "s|/etc/nginx/certs/dev-server\\.key|${SSL_CERT_KEY}|g" \
    -e "s|/etc/nginx/certs/__SSL_CERT_BASENAME__\\.fullchain\\.crt|${SSL_CERT_FILE}|g" \
    -e "s|/etc/nginx/certs/__SSL_CERT_BASENAME__\\.crt|${SSL_CERT_FILE}|g" \
    -e "s|/etc/nginx/certs/__SSL_CERT_BASENAME__\\.key|${SSL_CERT_KEY}|g" \
    -e "s|/etc/nginx/certs/\\([a-zA-Z0-9._-]*\\)\\.fullchain\\.crt|/etc/nginx/certs/\\1.crt|g" \
    "$f"
}
