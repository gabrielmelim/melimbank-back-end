#!/usr/bin/env bash
set -e
awslocal s3 mb s3://melimbank-bucket
awslocal sqs create-queue --queue-name melimbank-transactions
TOPIC_ARN=$(awslocal sns create-topic --name melimbank-events --query TopicArn --output text)
QUEUE_URL=$(awslocal sqs get-queue-url --queue-name melimbank-transactions --query QueueUrl --output text)
QUEUE_ARN=$(awslocal sqs get-queue-attributes --queue-url "$QUEUE_URL" --attribute-names QueueArn --query Attributes.QueueArn --output text)
awslocal sns subscribe --topic-arn "$TOPIC_ARN" --protocol sqs --notification-endpoint "$QUEUE_ARN"
awslocal dynamodb create-table   --table-name audit_events   --attribute-definitions AttributeName=id,AttributeType=S   --key-schema AttributeName=id,KeyType=HASH   --billing-mode PAY_PER_REQUEST
echo "LocalStack pronto (S3/SQS/SNS/DynamoDB)."
