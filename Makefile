# Makefile gốc repo — `make help`
# Chi tiết: Makefile.docker.mk, Makefile.function.mk, Makefile.exec.mk

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
MAKEFLAGS += --no-print-directory

include Makefile.docker.mk
include Makefile.function.mk
include Makefile.exec.mk

.PHONY: help
.DEFAULT_GOAL := help

help:
	@echo "Repo: $(ROOT)"
	@echo ""
	@echo "Docker stack (Makefile.docker.mk):"
	@echo "  make up | up-all          — gateway + DB + dev services nhẹ (không LocalStack)"
	@echo "  make down | down-all      — compose down (giữ volume)"
	@echo "  make stop | stop-all      — stop container (giữ container)"
	@echo "  make restart | restart-all"
	@echo "  make ps | logs | pull"
	@echo ""
	@echo "  make up-gateway | down-gateway | restart-gateway  (alias: gw-stop | gw-restart)"
	@echo "  make up-mysql     — mysql + mysql-80 + phpmyadmin"
	@echo "  make up-postgres  — postgres + pgadmin"
	@echo "  make up-redis     — redis + redis-commander"
	@echo "  make up-localstack — localstack + stackport (chạy riêng khi cần)"
	@echo "  make up-mailpit | up-mock"
	@echo "  (down-* / restart-* tương ứng từng nhóm trên)"
	@echo ""
	@echo "  make docker-stop-all      — dừng mọi container Docker trên máy"
	@echo ""
	@echo "Script tiện ích (Makefile.function.mk):"
	@echo "  make gen-sites | gw    — sites.example (infra) + routes.json (project)"
	@echo "  make init-sites        — chỉ copy sites.example → gateway/sites"
	@echo "  make gw-safe           — gen-sites + up gateway + nginx -t"
	@echo "  make hosts             — print-hosts-from-env.sh (WSL + Windows)"
	@echo "  make gen-ssl | ssl     — cert TLS (\$${PROJECT_NAME}.\$${SSL_DOMAIN_BASE}.crt) + gen-sites"
	@echo "  make certs-combined    — refresh certs/combined-ca.pem only"
	@echo ""
	@echo "Exec shell (Makefile.exec.mk):"
	@echo "  make exec SVC=<alias> [CMD='...']  |  make exec <alias>  |  make exec-list"
	@echo "  vd. make exec SVC=gateway | make exec mysql | make exec localstack"
