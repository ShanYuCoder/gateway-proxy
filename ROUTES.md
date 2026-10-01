# Local dev — quy ước

Chỉnh **`routes.json`** (`cp routes.json.example routes.json`). Cần `python3` (parser: `lib/routes-emit.py`).

## Quy ước

- Mọi `host` trong JSON: **`something.<SSL_DOMAIN_BASE>`** (vd. `saas-api.local.com`). Cert SAN: `SSL_DOMAIN_BASE` + `*.<base>` — không đọc từng host khi gen SSL.
- File cert nginx: `certs/${PROJECT_NAME}.${SSL_DOMAIN_BASE}.crt` + `.key` (mount vào gateway `/etc/nginx/certs/`).
- **API / portal không publish cổng ra host** — gateway proxy qua `base_shared_net`:
  - API: `<stack>-api-nginx:<port>` — `stack` trong `api.stack`
  - Portal: `<stack>-portal-node:<port>`
- **`port` (tùy chọn, từng entry)** — mỗi domain có thể listen cổng khác nhau (Nuxt 3000, NestJS 4000, …):
  - `api.port` — mặc định `80` nếu không khai báo
  - `portals[].port` — mặc định `3000` nếu không khai báo
- **`internal` (tùy chọn trên `api`)**: Host header gateway gửi vào `<stack>-api-nginx` (phải khớp `server_name` nginx trong container API). **Mặc định = `api.host`** nếu bỏ qua. Chỉ khai báo khi khác host public — vd. browser `api-base.local.com` nhưng API nginx vẫn `laravel.api.com`.
- Thêm project: sửa JSON → `make gen-sites` + `make hosts`. **Không** cần `make gen-ssl` lại.

## Schema (tóm tắt)

- `shared[]`: `{ "title", "hosts": [...] }`
- `projects.<slug>` (compose nội bộ): `{ "api": { host, stack, internal, port? }, "portals": [{ host, stack, port? }] }`
- **`external: true`** — upstream khai báo **trên từng `sites[]`**, không thêm biến `.env` theo từng stack:
  - **`role: web`** + **`container`** + **`docroot`** → gateway FastCGI `:9000` (Laravel/PHP)
  - **`role: web`** + **`proxy`** (vd. `http://dev_nginx:8082`) → proxy HTTP tới stack có nginx riêng
  - **`role: node`** + **`container`** + **`port`** → proxy dev server (Nuxt/Vite)
- `.env` chỉ giữ **`MAIRY_PROJECT_WORKSPACE` / `WEBBEDS_PROJECT_WORKSPACE`** (mount docroot vào gateway cho fastcgi) — tên container/docroot nằm trong JSON.

## Mẫu trên git

**`routes.json.example`**: hai project `global` (api/portal compose) và `globalExternal` (sites external). Copy → `routes.json` rồi thay bằng project thật; thêm nhiều portal, `portals[]`-only, `proxy`, … theo schema trên.

## Ví dụ ngắn

```json
"api": {
  "host": "saas-api.local.com",
  "stack": "saas",
  "port": 8080
},
"portals": [
  { "host": "tenant-api.local.com", "stack": "tenant-api", "port": 4000 },
  { "host": "tenant-admin.local.com", "stack": "tenant-admin" }
]
```

External (mairy / webbeds — cùng schema):

```json
"sites": [
  {
    "host": "webbeds-api.local.com",
    "role": "web",
    "container": "dev_webbeds_php",
    "docroot": "/var/www/html/public"
  },
  {
    "host": "webbeds.local.com",
    "role": "node",
    "container": "dev_webbeds_frontend_node",
    "port": 8080
  }
]
```

## Lệnh

```bash
make gen-sites   # infra từ sites.example + project từ routes.json
make init-sites  # chỉ infra (phpmyadmin, mail, mock, …)
make hosts       # hosts.sample
make gen-ssl     # cert ${PROJECT_NAME}.${SSL_DOMAIN_BASE}.crt + gen-sites + nhắc Windows trust
```
