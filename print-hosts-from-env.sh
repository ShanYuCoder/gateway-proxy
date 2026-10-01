#!/usr/bin/env bash
# Usage: bash print-hosts-from-env.sh [.env]
#   sh … cũng được — tự chuyển sang bash (dash không có pipefail)

if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
OUTPUT_FILE="$SCRIPT_DIR/hosts.sample"
WSL_HOSTS="/etc/hosts"
WIN_HOSTS="/mnt/c/Windows/System32/drivers/etc/hosts"
# Đường dẫn hiển thị cho user trên Windows (dán trong Notepad với quyền Administrator).
WIN_HOSTS_PATH_DISPLAY='C:\Windows\System32\drivers\etc\hosts'

ENV_FILE="$SCRIPT_DIR/.env"

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      echo "Usage: $0 [path-to-env-file]" >&2
      echo "  Ghi $OUTPUT_FILE, merge khối BEGIN/END vào WSL + Windows hosts (backup)." >&2
      exit 0
      ;;
    *)
      ENV_FILE="$arg"
      ;;
  esac
done

case "$ENV_FILE" in
  */*) ENV_SOURCE="$ENV_FILE" ;;
  *) ENV_SOURCE="./$ENV_FILE" ;;
esac

if [ ! -f "$ENV_SOURCE" ]; then
  echo "Env file not found: $ENV_FILE" >&2
  echo "Usage: $0 [path-to-env-file]" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$ENV_SOURCE"
set +a

IP="${HOSTS_IP:-127.0.0.1}"

# shellcheck source=lib/routes-json.sh
source "$SCRIPT_DIR/lib/routes-json.sh"
routes_json_init "$SCRIPT_DIR" || exit 1

ENTRIES_TMP=$(mktemp)
: >"$ENTRIES_TMP"
have=0
last_title=""
while IFS=$'\t' read -r _scope title host || [[ -n "${title:-}" ]]; do
  [[ -z "${host:-}" ]] && continue
  have=1
  if [[ "$title" != "$last_title" ]]; then
    [[ -n "$last_title" ]] && printf '\n' >>"$ENTRIES_TMP"
    printf '%s\n' "##" >>"$ENTRIES_TMP"
    printf '%s\n' "# ${title}" >>"$ENTRIES_TMP"
    printf '%s\n' "##" >>"$ENTRIES_TMP"
    last_title="$title"
  fi
  printf '%-16s%s\n' "$IP" "$host" >>"$ENTRIES_TMP"
done < <(routes_json_hostlines)

if [[ "$have" -eq 0 ]]; then
  echo "No hosts in $ROUTES_JSON" >&2
  exit 1
fi
printf '\n' >>"$ENTRIES_TMP"

# Marker block: idempotent re-run replaces only this project's section.
PROJECT_SLUG=$(printf '%s' "${PROJECT_NAME:-default}" | tr -cd 'a-zA-Z0-9_-')
[ -z "$PROJECT_SLUG" ] && PROJECT_SLUG=default
BEGIN_MARK="# BEGIN docker-hosts-${PROJECT_SLUG}"
END_MARK="# END docker-hosts-${PROJECT_SLUG}"
# Viền: ## + '-' dài ≈ dòng BEGIN (+ 4 ký tự), tối thiểu 12 ký tự tổng.
sep_total=$((${#BEGIN_MARK} + 4))
[ "$sep_total" -lt 12 ] && sep_total=12
dash_n=$((sep_total - 2))
[ "$dash_n" -lt 1 ] && dash_n=1
TOP_SEP=$(printf '##%s' "$(awk -v n="$dash_n" 'BEGIN { while (n-- > 0) printf "-" }')")
BOT_SEP="$TOP_SEP"

write_managed_hosts_block() {
  _entries="$1"
  printf '%s\n' "$TOP_SEP" "$BEGIN_MARK" "$BOT_SEP"
  cat "$_entries"
  printf '%s\n' "$TOP_SEP" "$END_MARK" "$BOT_SEP"
}

write_managed_hosts_block "$ENTRIES_TMP" > "$OUTPUT_FILE"
printf "Generated %s from %s\n" "$OUTPUT_FILE" "$ENV_FILE"
cat "$OUTPUT_FILE"

merge_block_into_file() {
  target="$1"
  mode="$2"

  tmp_out=$(mktemp)
  tmp_managed=$(mktemp)
  tmp_merge=$(mktemp)
  cleanup() {
    rm -f "$tmp_out" "$tmp_managed" "$tmp_merge"
  }
  trap cleanup EXIT

  if [ ! -f "$target" ] || [ ! -r "$target" ]; then
    echo "[WARN] Cannot read $target — skip." >&2
    trap - EXIT
    cleanup
    return 1
  fi

  write_managed_hosts_block "$ENTRIES_TMP" > "$tmp_managed"

  # Đọc cả file vào bộ nhớ rồi bỏ khối đã đánh dấu; tránh mất nội dung nếu khối lỗi / không đóng.
  # Kết quả = nội dung hosts cũ (trừ khối cũ) + khối mới — không phải chỉ ghi mỗi khối.
  if ! awk -v top="$TOP_SEP" -v bot="$BOT_SEP" -v leg_top="##_______" -v leg_bot="##______" \
    -v beg="$BEGIN_MARK" -v end="$END_MARK" '
    function open_tri(i,    li) {
      li = lines[i]
      if (i + 2 > n) return 0
      if ((li == top && lines[i + 1] == beg && lines[i + 2] == bot) || \
          (li == leg_top && lines[i + 1] == beg && lines[i + 2] == leg_bot))
        return 1
      return 0
    }
    function close_tri(i,    li) {
      li = lines[i]
      if (i + 2 > n) return 0
      if ((li == top && lines[i + 1] == end && lines[i + 2] == bot) || \
          (li == leg_top && lines[i + 1] == end && lines[i + 2] == leg_bot))
        return 1
      return 0
    }
    { sub(/\r$/, ""); lines[++n] = $0 }
    END {
      skip = 0
      for (i = 1; i <= n; i++) {
        line = lines[i]
        if (skip == 0 && open_tri(i)) {
          skip = 1
          i += 2
          continue
        }
        if (skip == 1 && close_tri(i)) {
          skip = 0
          i += 2
          continue
        }
        if (skip == 1) {
          if (line == end) skip = 0
          continue
        }
        if (line == beg) {
          skip = 1
          continue
        }
        print line
      }
      if (skip) {
        print "ERROR: unclosed docker-hosts block in hosts file (missing # END ... or footer)." > "/dev/stderr"
        exit 2
      }
    }
  ' "$target" > "$tmp_out"; then
    echo "[ERROR] Refusing to change $target — fix markers or hosts syntax, then retry." >&2
    trap - EXIT
    cleanup
    return 1
  fi

  {
    cat "$tmp_out"
    cat "$tmp_managed"
  } > "$tmp_merge"

  ok=0
  if [ "$mode" = "sudo" ]; then
    bak="${target}.bak.print-hosts-$(date +%Y%m%d%H%M%S)"
    if sudo cp -a "$target" "$bak" 2>/dev/null; then
      echo "[INFO] Backup: $bak"
    else
      echo "[WARN] Could not create backup of $target (continuing)." >&2
    fi
    if sudo cp "$tmp_merge" "$target"; then
      ok=1
    else
      echo "[WARN] Could not write $target (sudo failed or cancelled)." >&2
    fi
  else
    bak="${target}.bak.print-hosts-$(date +%Y%m%d%H%M%S)"
    if cp "$target" "$bak" 2>/dev/null; then
      echo "[INFO] Backup: $bak"
    else
      echo "[WARN] Could not create backup of $target (continuing)." >&2
    fi
    if cp "$tmp_merge" "$target"; then
      ok=1
    else
      echo "[WARN] Could not write Windows hosts from WSL (cần quyền Administrator)." >&2
      echo "[HINT] Mở $OUTPUT_FILE — copy toàn bộ nội dung — mở Notepad (Run as administrator) tại:" >&2
      echo "       $WIN_HOSTS_PATH_DISPLAY" >&2
      echo "       rồi dán; xóa khối cũ giữa cùng BEGIN/END nếu đã có." >&2
    fi
  fi

  trap - EXIT
  cleanup
  return "$((1 - ok))"
}

echo "[INFO] Merging into WSL $WSL_HOSTS ..."
merge_block_into_file "$WSL_HOSTS" sudo && echo "[INFO] WSL hosts updated." || true

if [ -f "$WIN_HOSTS" ]; then
  echo "[INFO] Merging into Windows hosts ($WIN_HOSTS) ..."
  merge_block_into_file "$WIN_HOSTS" user && echo "[INFO] Windows hosts updated." || true
else
  echo "[WARN] Windows hosts not found at $WIN_HOSTS (WSL has no C: mount?)." >&2
  echo "[HINT] Trên Windows: mở $OUTPUT_FILE, copy toàn bộ, dán vào (Notepad as Administrator):" >&2
  echo "       $WIN_HOSTS_PATH_DISPLAY" >&2
fi

rm -f "$ENTRIES_TMP"
