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
- **`internal`**: Host header gateway gửi vào nginx PHP (khớp `server_name` trong `default.conf`); đặt trong `api.internal`.
- **Mairy external** vẫn dùng cổng publish host (sẽ bỏ sau).
- Thêm project: sửa JSON → `make gen-sites` + `make hosts`. **Không** cần `make gen-ssl` lại.

## Schema (tóm tắt)

- `shared[]`: `{ "title", "hosts": [...] }`
- `projects.<slug>`: `{ "api": { host, stack, internal, port? }, "portals": [{ host, stack, port? }] }` hoặc `{ "external": true, "sites": [...] }`
- **Webbeds** (`external` + `role: "app"`): thêm trên project `phpContainer`, `nodeContainer`, `docroot` (không đặt trong `.env`).
- `<slug>` project = nhóm trong hosts file; **`stack`** = tên container trên Docker network (có thể khác slug).

## Ví dụ

```json
"api": {
  "host": "saas-api.local.com",
  "stack": "saas",
  "internal": "saas-api.local.com",
  "port": 8080
},
"portals": [
  { "host": "amano-parking-api.local.com", "stack": "amano-api", "port": 4000 },
  { "host": "amano-parking-chain.local.com", "stack": "amano-chain" }
]
```

→ `amano-api-portal-node:4000`, `amano-chain-portal-node:3000`, `saas-api-nginx:8080`.

Webbeds (Vue + Laravel API qua gateway):

```json
"webbeds": {
  "external": true,
  "phpContainer": "dev_webbeds_php",
  "nodeContainer": "dev_webbeds_frontend_node",
  "docroot": "/var/www/html/public",
  "sites": [
    { "host": "webbeds.local.com", "port": 8080, "role": "app" }
  ]
}
```

→ `sites[].port` = cổng Nuxt trong container; tên container khớp `~/docker-webbeds` + `PROJECT_NAME`.

## Lệnh

```bash
make gen-sites   # infra từ sites.example + project từ routes.json
make init-sites  # chỉ infra (phpmyadmin, mail, mock, …)
make hosts       # hosts.sample
make gen-ssl     # cert ${PROJECT_NAME}.${SSL_DOMAIN_BASE}.crt + gen-sites + nhắc Windows trust
```
