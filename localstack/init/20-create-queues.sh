#!/usr/bin/env bash
set -euo pipefail

echo "[INIT] Creating SQS queues..."

export AWS_ACCESS_KEY_ID=x
export AWS_SECRET_ACCESS_KEY=x
export AWS_DEFAULT_REGION=us-east-1

ENDPOINT_URL="http://localstack:4566"

for queue in \
  queue_mail_booking.fifo \
  queue_default.fifo \
  queue_msg_line.fifo \
  queue_msg_mail.fifo \
  queue_msg_sms.fifo \
  queue_booking_to_3daikan.fifo \
  queue_send_log.fifo \
  queue_crawl_task.fifo \
  queue_crawl_nat_task.fifo
 do
  aws --endpoint-url="$ENDPOINT_URL" sqs create-queue \
    --queue-name "$queue" \
    --attributes FifoQueue=true,ContentBasedDeduplication=true \
    2>/dev/null || true

  echo "Queue ready: $queue"
 done

echo "[INIT] SQS queues created."
