#!/usr/bin/env bash
set -euo pipefail

awslocal sns create-topic \
	--name ses-mairy-email--booking-topic 2>/dev/null || true

echo "SNS topic ready: ses-mairy-email--booking-topic"
