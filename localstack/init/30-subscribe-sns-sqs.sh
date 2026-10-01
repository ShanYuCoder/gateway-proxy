#!/usr/bin/env bash
set -euo pipefail

TOPIC_ARN=$(awslocal sns list-topics \
  --query "Topics[?contains(TopicArn, 'ses-mairy-email--booking-topic')].TopicArn | [0]" \
  --output text)

if [ -z "$TOPIC_ARN" ] || [ "$TOPIC_ARN" = "None" ]; then
  echo "SNS topic not found, skip subscribe"
  exit 0
fi

QUEUE_URL=$(awslocal sqs get-queue-url \
  --queue-name queue_mail_booking.fifo \
  --output text)

QUEUE_ARN=$(awslocal sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-names QueueArn \
  --query 'Attributes.QueueArn' \
  --output text)

awslocal sns subscribe \
  --topic-arn "$TOPIC_ARN" \
  --protocol sqs \
  --notification-endpoint "$QUEUE_ARN" >/dev/null

echo "SNS subscribed to SQS"
