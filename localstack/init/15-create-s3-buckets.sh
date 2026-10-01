#!/usr/bin/env bash
set -euo pipefail

echo "[INIT] Creating S3 buckets..."

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

for bucket in \
  smart-media \
  tm-39mail-logs \
  fullsco-local-public \
  fullsco-local-private \
  scenario-local-public \
  scenario-local-private
do
  awslocal s3 mb "s3://${bucket}" 2>/dev/null || true
  echo "Bucket ready: ${bucket}"
done

echo "[INIT] S3 buckets created."
