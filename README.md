# Dev Environment (Docker Gateway)

Hạ tầng local dùng chung: **gateway HTTPS**, MySQL, PostgreSQL, Redis, Mailpit, mock API. LocalStack chạy riêng khi project cần S3/SQS/SNS/Logs.  
Các project (API, portal, …) **có thể nằm ở bất kỳ thư mục nào** — chỉ cần container join đúng Docker network và khớp `routes.json`.

## Cấu trúc repo này

```
dev_env/
├── .env                      ← cấu hình chính (cp từ .env.example)
├── routes.json               ← domain + upstream (cp từ routes.json.example — không commit)
├── docker-compose.yml        ← gateway, MySQL, phpMyAdmin, pgAdmin
├── docker-compose.services.yml   ← LocalStack, Mailpit, mock, StackPort
├── gateway/sites/            ← nginx conf cá nhân (make gen-sites — không commit)
├── gateway/sites.example/    ← template infra trong git (phpmyadmin, pgadmin, …)
├── certs/                    ← TLS: ${PROJECT_NAME}.${SSL_DOMAIN_BASE}.crt + dev-rootCA.crt
└── Makefile                  ← make help
```

## Bắt đầu nhanh (dev_env)

```bash
cp .env.example .env
cp routes.json.example routes.json
make init-sites       # infra conf (phpmyadmin, mail, …) — hoặc make gen-sites
make gen-ssl          # lần đầu: cert + cập nhật gateway sites
make hosts            # hosts.sample → /etc/hosts (WSL + Windows)
make up-all           # gateway + DB + dev services nhẹ, không LocalStack
# make up-localstack  # chỉ bật thêm khi project cần S3/SQS/SNS/Logs
```

Hoặc từng nhóm: `make up-gateway`, `make up-mysql`, `make up-localstack`, … (xem `make help`).

Sau đó bật compose của từng project (xem mục dưới). Chi tiết lệnh: **`make help`**

## Cấu hình `.env`

| Biến | Mô tả |
|------|--------|
| `PROJECT_NAME` | Tiền tố container/volume; phần tên file cert (`<PROJECT>.<SSL_DOMAIN_BASE>.crt`) |
| `SSL_DOMAIN_BASE` | Suffix domain (vd. `local.com`); SAN cert = base + `*.<base>` |
| `BASE_SHARED_NETWORK_NAME` | **Tên mạng Docker chung** (external) — project bên ngoài join cùng tên |
| `DATA_PATH_HOST` | Prefix folder data DB trên host (mặc định `./data`; subpath: mysql, mysql80, postgres, redis) |
| `HOSTS_IP` | IP ghi vào hosts (thường `127.0.0.1`) |
| `HOST_UID` / `HOST_GID` | Khớp user host (`id -u`, `id -g`) |

## Docker cho project (ở ngoài `dev_env`)

### Nguyên tắc

1. **Chuẩn bị gateway trước** — `make init-sites` / `make gen-sites` + `make gen-ssl` + `make hosts`.
2. **Bật stack mặc định** — `make up-all` (tự tạo mạng `BASE_SHARED_NETWORK_NAME` + folder `gateway/sites` nếu thiếu; không bật LocalStack).
3. **Bật LocalStack khi cần** — `make up-localstack` cho project dùng S3/SQS/SNS/Logs.
4. **Compose project join mạng external** — không publish cổng app ra host (gateway proxy).
5. **Đăng ký domain** trong `routes.json` → `make gen-sites` + `make hosts` + `make gw-restart`.
6. **`stack` trong JSON** phải khớp tiền tố tên container trên mạng.

### Quy ước tên container (gateway proxy tới)

| Loại | Tên container | Cổng trong mạng |
|------|---------------|-----------------|
| API (Laravel) | `<stack>-api-nginx` | mặc định `80` — `api.port` trong routes.json |
| Portal (Nuxt/Nest/…) | `<stack>-portal-node` | mặc định `3000` — `port` trên từng entry `portals[]` |

Ví dụ: `"stack": "saas"` → `saas-api-nginx:80` (hoặc `api.port` nếu khai báo).  
Portal NestJS: `{ "stack": "amano-api", "port": 4000 }` → `amano-api-portal-node:4000`.

### Mẫu `docker-compose.yml` — API

Đặt trong project bất kỳ (vd. `~/workspace/my-api/docker/`):

```yaml
name: api-${API_STACK_PREFIX:-myapp}

services:
  api-php:
    container_name: ${API_STACK_PREFIX:-myapp}-api-php
    # build / volumes …
    networks:
      - shared

  api-nginx:
    container_name: ${API_STACK_PREFIX:-myapp}-api-nginx
    image: nginx:1.27-alpine
    depends_on: [api-php]
    # volumes / default.conf …
    networks:
      - shared

networks:
  shared:
    name: ${BASE_SHARED_NETWORK_NAME:-base_shared_net}
    external: true
```

`.env` của project:

```bash
API_STACK_PREFIX=myapp
BASE_SHARED_NETWORK_NAME=base_shared_net   # khớp dev_env/.env
HOST_UID=1000
HOST_GID=1000
```

Chạy (từ thư mục chứa compose):

```bash
docker compose --env-file .env up -d
```

### Mẫu `docker-compose.yml` — Portal (Nuxt)

```yaml
name: portal-${PORTAL_STACK_PREFIX:-myapp}

services:
  frontend-node:
    container_name: ${PORTAL_STACK_PREFIX:-myapp}-portal-node
    # image node:24, pnpm dev listen :3000 …
    networks:
      - shared

networks:
  shared:
    name: ${BASE_SHARED_NETWORK_NAME:-base_shared_net}
    external: true
```

`.env`:

```bash
PORTAL_STACK_PREFIX=myapp-admin
BASE_SHARED_NETWORK_NAME=base_shared_net
```

### Đăng ký gateway

Thêm vào `dev_env/routes.json`:

```json
"myproject": {
  "api": {
    "host": "myapp-api.local.com",
    "stack": "myapp",
    "internal": "myapp-api.local.com"
  },
  "portals": [
    { "host": "myapp-admin.local.com", "stack": "myapp-admin" }
  ]
}
```

Rồi trong `dev_env`:

```bash
make gen-sites
make hosts
make gw-restart
```

Trình duyệt: `https://myapp-api.local.com` (sau SSL + hosts).

### Kết nối DB / dịch vụ shared từ container project

Trên `base_shared_net`, dùng **tên service Docker** (không dùng `127.0.0.1`):

| Dịch vụ | Host trong container |
|---------|----------------------|
| MySQL 8.4 | `mysql` |
| PostgreSQL | `postgres` / alias `saas-postgres` |
| Redis | `redis` :6379 |
| LocalStack | `localstack` |
| Mailpit SMTP | `mailpit` :1025 |
| HTTPS tới domain local | `https://mail.local.com` (gateway resolve qua DNS alias trên mạng) |

MySQL cũng expose `127.0.0.1:3306` ra host nếu cần chạy artisan/test ngoài container.

**Data DB** bind ra folder host (kiểu Laradock), không dùng Docker named volume. Chỉ cấu hình prefix `DATA_PATH_HOST` trong `.env`; subfolder tự nối trong compose:

| Instance | Subfolder |
|----------|-----------|
| MySQL 8.4 (`mysql`) | `mysql` |
| MySQL 8.0 (`mysql-80`) | `mysql80` |
| PostgreSQL (`postgres`) | `postgres` |
| Redis (`redis`) | `redis` |

| `DATA_PATH_HOST` | Kết quả |
|------------------|---------|
| (rỗng / không set) | `./data/mysql`, `./data/mysql80`, … |
| `~/env_data` | `~/env_data/mysql`, `~/env_data/mysql80`, … |

Bind mount: `docker compose up` tự tạo folder trên host nếu chưa có (đúng quyền cho container DB).

Chuyển data từ volume Docker cũ (một lần, thay `dev_*` theo `PROJECT_NAME`):

```bash
make down-all
mkdir -p data/mysql data/mysql80 data/postgres data/redis
docker run --rm -v dev_mysql_data:/from -v "$(pwd)/data/mysql":/to alpine cp -a /from/. /to/
docker run --rm -v dev_mysql_80_data:/from -v "$(pwd)/data/mysql80":/to alpine cp -a /from/. /to/
docker run --rm -v dev_postgres_data:/from -v "$(pwd)/data/postgres":/to alpine cp -a /from/. /to/
docker run --rm -v dev_redis_data:/from -v "$(pwd)/data/redis":/to alpine cp -a /from/. /to/
make up-all
```

### Checklist project mới

- [ ] `BASE_SHARED_NETWORK_NAME` khớp `dev_env/.env`
- [ ] Container đặt tên đúng `<stack>-api-nginx` / `<stack>-portal-node`
- [ ] Không `ports:` publish cổng app (443/80 do gateway lo)
- [ ] Đã thêm host vào `routes.json`
- [ ] `make gen-sites` + `make hosts` + `make gw-restart`
- [ ] `make up-all` chạy trước khi `docker compose up` project
- [ ] `make up-localstack` nếu project dùng LocalStack

## Hosts file

`make hosts` ghi `hosts.sample` và merge vào:
- **WSL:** `/etc/hosts`
- **Windows:** `C:\Windows\System32\drivers\etc\hosts`

## Lệnh Makefile

| Nhóm | Lệnh |
|------|------|
| Toàn stack | `up`, `up-all`, `down`, `down-all`, `stop`, `stop-all`, `restart`, `restart-all`, `ps`, `logs` (`up-all` không bật LocalStack) |
| Theo nhóm | `up-mysql`, `up-postgres`, `up-redis`, `up-localstack`, `up-mailpit`, `up-mock`, `up-gateway` (+ `down-*`, `restart-*`) |
| Cấu hình | `gen-sites`, `gen-ssl`, `hosts`, `gw-restart` |
| Exec shell | `make exec SVC=gateway`, `make exec mysql`, `make exec-list` |
| Dừng hết máy | `docker-stop-all` |

## URL (sau hosts + SSL)

| Dịch vụ | URL |
|---------|-----|
| API / Portal project | Theo `routes.json` |
| phpMyAdmin | https://phpmyadmin.local.com |
| pgAdmin | https://pgadmin.local.com |
| Redis Commander | https://redisadmin.local.com |
| Mailpit | http://mail.local.com |
| Mock API | http://mock.local.com |
| StackPort | http://stackport.local.com (`make up-localstack`) |

## SSL (WSL + Windows)

Cert nginx: `certs/${PROJECT_NAME}.${SSL_DOMAIN_BASE}.crt` + `.key` (vd. `dev.local.com.crt`).  
SAN: `SSL_DOMAIN_BASE` + `*.<SSL_DOMAIN_BASE>`. CA local: `certs/dev-rootCA.crt`.

```bash
make gen-ssl
# Windows (Admin): C:\Users\Public\dev_ssl\<PROJECT_NAME>\install-windows-trust.bat
```

Chi tiết domain: **`ROUTES.md`**

## Ghi chú

- Nhiều clone `dev_env` trên một máy: đặt `BASE_SHARED_NETWORK_NAME` **khác nhau** mỗi clone; project `.env` phải khớp clone đang dùng.
- Mạng `external`: `make up` / `up-all` tự `docker network create` nếu chưa có. Nếu lỗi label cũ: `make down-all` → `docker network rm base_shared_net` → `make up-all`.
- `gateway/sites/` phải writable — chạy `make init-sites` hoặc `make gen-sites` **trước** `docker compose up` lần đầu (tránh folder root-owned).
- Thêm host mới: sửa `routes.json` → `make gen-sites` — **không** cần `make gen-ssl` lại.
