#!/usr/bin/env bash
set -euo pipefail

echo "[INIT] Creating CloudWatch Logs groups (LocalStack)..."

# Khớp CLOUDWATCH_* trong mairy-backend/.env (dev)
for group in \
  "TM-39mail-Dev-CWgroup" \
  "/39mail/Dev" \
  "/39mail/Restaurant/Dev"
do
  awslocal logs create-log-group --log-group-name "$group" 2>/dev/null || true
  echo "Log group ready: ${group}"
done

echo "[INIT] CloudWatch Logs groups created (streams tạo tự động khi ghi log lần đầu)."
