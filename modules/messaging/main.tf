# Dead Letter Queue (DLQ) — always create this first
# Messages land here after 3 failed processing attempts.
# Nothing is ever lost — failed messages wait here for investigation.
resource "aws_sqs_queue" "bookings_dlq" {
  name                      = "${var.name_prefix}-bookings-dlq"
  message_retention_seconds = 1209600 # 14 days (max)

  tags = {
    Name = "${var.name_prefix}-bookings-dlq"
  }
}

# Main Queue
resource "aws_sqs_queue" "booking_events" {
  name                       = "${var.name_prefix}-booking-events"
  delay_seconds              = 0      # delay before message is visible
  max_message_size           = 262144 # 256KB max
  message_retention_seconds  = 86400  # 1 day
  receive_wait_time_seconds  = 10     # long polling — wait up to 10s for messages
  visibility_timeout_seconds = 30     # how long a message is hidden after received

  # --- Dead Letter Queue config ---
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.bookings_dlq.arn
    maxReceiveCount     = 3 # after 3 failed attempts → goes to DLQ
  })

  sqs_managed_sse_enabled = true # encryption

  tags = {
    Name = "${var.name_prefix}-booking-events"
  }
}


data "aws_caller_identity" "current" {}

resource "aws_sqs_queue_policy" "booking_events" {
  queue_url = aws_sqs_queue.booking_events.url

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEC2ToSendMessages"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.booking_events.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}



# SNS Topic
resource "aws_sns_topic" "booking_notifications" {
  name         = "${var.name_prefix}-booking-notifications"
  display_name = "My App Notifications"

  tags = {
    Name = "${var.name_prefix}-booking-notifications"
  }
}


# Subscribe SQS to SNS — SNS fans out to SQS
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.booking_notifications.arn
  protocol  = "email"
  endpoint  = var.admin_email
}