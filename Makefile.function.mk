# Script tiện ích (gateway sites, hosts, SSL).

.PHONY: gen-sites init-sites hosts gen-ssl certs-combined gw gw-safe ssl

# Copy gateway/sites.example → gateway/sites (infra). Thay __SSL_CERT_BASENAME__ từ .env.
init-sites:
	@bash -c 'set -euo pipefail; \
	  ROOT="$(ROOT)"; \
	  [ -f "$$ROOT/.env" ] && set -a && . "$$ROOT/.env" && set +a; \
	  source "$$ROOT/lib/ssl-cert-names.sh"; ssl_cert_load_paths; \
	  mkdir -p "$$ROOT/gateway/sites"; \
	  if [ ! -w "$$ROOT/gateway/sites" ]; then \
	    echo "[ERROR] $$ROOT/gateway/sites not writable." >&2; \
	    echo "  Fix (docker): docker run --rm -v $$ROOT/gateway/sites:/sites alpine chown -R $$(id -u):$$(id -g) /sites" >&2; \
	    exit 1; \
	  fi; \
	  for f in "$$ROOT/gateway/sites.example"/*.conf; do \
	    [ -f "$$f" ] || continue; \
	    base=$$(basename "$$f"); \
	    if [ ! -f "$$ROOT/gateway/sites/$$base" ]; then \
	      sed "s/__SSL_CERT_BASENAME__/$$SSL_CERT_BASENAME/g" "$$f" >"$$ROOT/gateway/sites/$$base"; \
	      echo "[INFO] Copied $$base"; \
	    fi; \
	  done'

gen-sites:
	bash "$(ROOT)/gen-gateway-sites.sh" "$(ROOT)/.env"

hosts:
	bash "$(ROOT)/print-hosts-from-env.sh" "$(ROOT)/.env"

# Cert: certs/${PROJECT_NAME}.${SSL_DOMAIN_BASE}.crt + gen-gateway-sites + combined CA
gen-ssl:
	bash "$(ROOT)/gen-dev-ssl.sh" "$(ROOT)/.env" "$(ROOT)/certs"
	bash "$(ROOT)/certs/refresh-combined-ca.sh"

certs-combined:
	bash "$(ROOT)/certs/refresh-combined-ca.sh"

gw: gen-sites

gw-safe: gen-sites
	docker compose --project-directory "$(ROOT)" up -d gateway-nginx
	docker compose --project-directory "$(ROOT)" exec -T gateway-nginx nginx -t

ssl: gen-ssl
