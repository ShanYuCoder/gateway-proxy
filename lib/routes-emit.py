#!/usr/bin/env python3
"""Đọc routes.json — stdout TSV cho bash (không cần jq).

Commands:
  records    — gateway: project\\trole\\thost\\tport\\tstack\\tinternal\\tphpContainer\\tnodeContainer\\tdocroot
  hostlines  — /etc/hosts: scope\\ttitle\\thost  (scope=shared|project slug)
  domains    — một hostname mỗi dòng (SSL SAN)

Port mặc định: API 80, portal 3000 — override bằng `port` trên từng entry api/portals[].
"""
from __future__ import annotations

import json
import sys
from pathlib import Path


def load(path: Path) -> dict:
    with path.open(encoding="utf-8") as f:
        return json.load(f)


DEFAULT_API_PORT = 80
DEFAULT_PORTAL_PORT = 3000
EMPTY_FIELD = "-"


def _field(value: str | int | None) -> str:
    if value is None or value == "":
        return EMPTY_FIELD
    return str(value)


def api_stack(api: dict, slug: str) -> str:
    return api.get("stack") or slug


def api_internal(api: dict, proj: dict) -> str:
    return api.get("internal") or proj.get("internal") or api["host"]


def emit_records(data: dict) -> None:
    for slug, proj in data.get("projects", {}).items():
        if proj.get("external"):
            php_c = _field(proj.get("phpContainer"))
            node_c = _field(proj.get("nodeContainer"))
            docroot = _field(proj.get("docroot"))
            for site in proj.get("sites", []):
                role = site.get("role", "web")
                print(
                    f"{slug}\t{role}\t{site['host']}\t{site['port']}\t"
                    f"{EMPTY_FIELD}\t{EMPTY_FIELD}\t{php_c}\t{node_c}\t{docroot}"
                )
        else:
            api = proj.get("api")
            if api:
                stack = api_stack(api, slug)
                internal = api_internal(api, proj)
                port = api.get("port", DEFAULT_API_PORT)
                print(
                    f"{slug}\tapi\t{api['host']}\t{port}\t{stack}\t{_field(internal)}\t"
                    f"{EMPTY_FIELD}\t{EMPTY_FIELD}\t{EMPTY_FIELD}"
                )
            for p in proj.get("portals", []):
                stack = p.get("stack") or p["host"].split(".")[0]
                port = p.get("port", DEFAULT_PORTAL_PORT)
                print(
                    f"{slug}\tportal\t{p['host']}\t{port}\t{stack}\t{EMPTY_FIELD}\t"
                    f"{EMPTY_FIELD}\t{EMPTY_FIELD}\t{EMPTY_FIELD}"
                )


def _append_unique_host(hosts: list[str], seen: set[str], host: str) -> None:
    if host and host not in seen:
        seen.add(host)
        hosts.append(host)


def emit_hostlines(data: dict) -> None:
    for block in data.get("shared", []):
        title = block.get("title", "Shared")
        seen: set[str] = set()
        hosts: list[str] = []
        for host in block.get("hosts", []):
            _append_unique_host(hosts, seen, host)
        for host in hosts:
            print(f"shared\t{title}\t{host}")
    for slug, proj in data.get("projects", {}).items():
        title = slug[:1].upper() + slug[1:] if slug else slug
        seen: set[str] = set()
        hosts: list[str] = []
        if proj.get("external"):
            for site in proj.get("sites", []):
                _append_unique_host(hosts, seen, site["host"])
        else:
            api = proj.get("api")
            if api:
                _append_unique_host(hosts, seen, api["host"])
                _append_unique_host(hosts, seen, api_internal(api, proj))
            for p in proj.get("portals", []):
                _append_unique_host(hosts, seen, p["host"])
        for host in hosts:
            print(f"project\t{title}\t{host}")


def emit_domains(data: dict) -> None:
    seen: set[str] = set()
    for block in data.get("shared", []):
        for host in block.get("hosts", []):
            if host not in seen:
                seen.add(host)
                print(host)
    for proj in data.get("projects", {}).values():
        if proj.get("external"):
            for site in proj.get("sites", []):
                h = site["host"]
                if h not in seen:
                    seen.add(h)
                    print(h)
        else:
            api = proj.get("api")
            if api:
                for h in (api["host"], api_internal(api, proj)):
                    if h not in seen:
                        seen.add(h)
                        print(h)
            for p in proj.get("portals", []):
                h = p["host"]
                if h not in seen:
                    seen.add(h)
                    print(h)


def main() -> int:
    if len(sys.argv) < 3:
        print("Usage: routes-emit.py <records|hostlines|domains> <path-to-routes.json>", file=sys.stderr)
        return 2
    cmd, path_s = sys.argv[1], sys.argv[2]
    path = Path(path_s)
    if not path.is_file():
        print(f"[ERROR] Missing routes file: {path}", file=sys.stderr)
        return 1
    data = load(path)
    if cmd == "records":
        emit_records(data)
    elif cmd == "hostlines":
        emit_hostlines(data)
    elif cmd == "domains":
        emit_domains(data)
    else:
        print(f"[ERROR] Unknown command: {cmd}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
