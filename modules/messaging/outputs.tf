output "sqs_queue_url" {
  description = "SQS queue URL - Flask sends booking events here"
  value       = aws_sqs_queue.booking_events.url
}

output "sqs_queue_arn" {
  description = "SQS queue ARN"
  value       = aws_sqs_queue.booking_events.arn
}

output "sns_topic_arn" {
  description = "SNS topic ARN - worker publishes booking notifications here"
  value       = aws_sns_topic.booking_notifications.arn
}

output "dlq_arn" {
  description = "Dead letter queue ARN - messages land here after 3 failed attempts"
  value       = aws_sqs_queue.bookings_dlq.arn
}