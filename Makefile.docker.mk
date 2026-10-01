# Docker Compose — docker-compose.yml + docker-compose.services.yml
# Nhóm UI đi kèm service chính: mysql↔phpmyadmin, postgres↔pgadmin, redis↔redis-commander, localstack↔stackport.

DC := docker compose --project-directory "$(ROOT)"
DCS := docker compose --project-directory "$(ROOT)" -f docker-compose.yml -f docker-compose.services.yml

SVC_MYSQL := mysql mysql-80 phpmyadmin
SVC_POSTGRES := postgres pgadmin
SVC_REDIS := redis redis-commander
SVC_LOCALSTACK := localstack stackport
SVC_MAILPIT := mailpit
SVC_MOCK := mock-api
SVC_GATEWAY := gateway-nginx
SVC_UP_ALL := $(SVC_GATEWAY) $(SVC_MYSQL) $(SVC_POSTGRES) $(SVC_REDIS) $(SVC_MAILPIT) $(SVC_MOCK)

.PHONY: ensure-shared-network ensure-gateway-sites \
	up up-all down down-all stop stop-all restart restart-all ps logs pull \
	up-gateway down-gateway restart-gateway \
	up-mysql down-mysql restart-mysql \
	up-postgres down-postgres restart-postgres \
	up-redis down-redis restart-redis \
	up-localstack down-localstack restart-localstack \
	up-mailpit down-mailpit restart-mailpit \
	up-mock down-mock restart-mock \
	gateway-stop gateway-restart gw-stop gw-restart docker-stop-all

ensure-gateway-sites:
	@mkdir -p "$(ROOT)/gateway/sites"
	@if [ ! -w "$(ROOT)/gateway/sites" ]; then \
	  echo "[ERROR] $(ROOT)/gateway/sites not writable (thường do compose up trước init-sites)." >&2; \
	  echo "  Fix (sudo): sudo chown -R \$$(id -u):\$$(id -g) $(ROOT)/gateway/sites" >&2; \
	  echo "  Fix (docker): docker run --rm -v $(ROOT)/gateway/sites:/sites alpine chown -R \$$(id -u):\$$(id -g) /sites" >&2; \
	  exit 1; \
	fi

ensure-shared-network:
	@bash -c 'set -a; [ -f "$(ROOT)/.env" ] && . "$(ROOT)/.env"; set +a; \
	  net="$${BASE_SHARED_NETWORK_NAME:-base_shared_net}"; \
	  docker network inspect "$$net" >/dev/null 2>&1 || docker network create "$$net"'

# --- Toàn stack ---
up up-all: ensure-shared-network ensure-gateway-sites
	$(DCS) up -d --remove-orphans $(SVC_UP_ALL)

down down-all:
	$(DCS) down --remove-orphans

stop stop-all:
	$(DCS) stop

restart restart-all:
	$(DCS) restart

ps:
	$(DCS) ps -a

logs:
	$(DCS) logs -f

pull:
	$(DCS) pull

docker-stop-all:
	@echo "[docker-stop-all] Stopping all running Docker containers on this machine..."
	@ids="$$(docker ps -q)"; \
	if [ -n "$$ids" ]; then \
		docker stop $$ids; \
		echo "[DONE] docker-stop-all"; \
	else \
		echo "[docker-stop-all] No running containers"; \
	fi

# --- Gateway ---
up-gateway: ensure-shared-network ensure-gateway-sites
	$(DCS) up -d $(SVC_GATEWAY)

down-gateway:
	$(DCS) stop $(SVC_GATEWAY)

restart-gateway:
	$(DCS) restart $(SVC_GATEWAY)

gateway-stop: down-gateway
gateway-restart: restart-gateway
gw-stop: down-gateway
gw-restart: restart-gateway

# --- MySQL + phpMyAdmin ---
up-mysql: ensure-shared-network
	$(DCS) up -d $(SVC_MYSQL)

down-mysql:
	$(DCS) stop $(SVC_MYSQL)

restart-mysql:
	$(DCS) restart $(SVC_MYSQL)

# --- PostgreSQL + pgAdmin ---
up-postgres: ensure-shared-network
	$(DCS) up -d $(SVC_POSTGRES)

down-postgres:
	$(DCS) stop $(SVC_POSTGRES)

restart-postgres:
	$(DCS) restart $(SVC_POSTGRES)

# --- Redis + Redis Commander ---
up-redis: ensure-shared-network
	$(DCS) up -d $(SVC_REDIS)

down-redis:
	$(DCS) stop $(SVC_REDIS)

restart-redis:
	$(DCS) restart $(SVC_REDIS)

# --- LocalStack + StackPort ---
up-localstack: ensure-shared-network
	$(DCS) up -d $(SVC_LOCALSTACK)

down-localstack:
	$(DCS) stop $(SVC_LOCALSTACK)

restart-localstack:
	$(DCS) restart $(SVC_LOCALSTACK)

# --- Mailpit ---
up-mailpit: ensure-shared-network
	$(DCS) up -d $(SVC_MAILPIT)

down-mailpit:
	$(DCS) stop $(SVC_MAILPIT)

restart-mailpit:
	$(DCS) restart $(SVC_MAILPIT)

# --- Mock API ---
up-mock: ensure-shared-network
	$(DCS) up -d $(SVC_MOCK)

down-mock:
	$(DCS) stop $(SVC_MOCK)

restart-mock:
	$(DCS) restart $(SVC_MOCK)
