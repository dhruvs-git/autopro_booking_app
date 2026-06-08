# Creating cloudwatch logs group where flask sends notifications
resource "aws_cloudwatch_log_group" "flask" {
  name              = "/${var.name_prefix}/flask"
  retention_in_days = 7

  tags = {
    Name = "${var.name_prefix}-flask-logs"
  }
}

# Two different systemd service running on EC2 
# we need other log group for worker
resource "aws_cloudwatch_log_group" "worker" {
  name              = "/${var.name_prefix}/worker"
  retention_in_days = 7

  tags = {
    Name = "${var.name_prefix}-worker-logs"
  }
}


# ALARM-1 EC2 HIGH CPU
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.name_prefix}-ec2-high-cpu"
  alarm_description   = "Triggers when CPU exceeds 80% for 10 minutes"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2 # must breach for 2 consecutive periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120 # check every 120 seconds
  statistic           = "Average"
  threshold           = 80 # trigger at 80% CPU

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }

  alarm_actions = [var.sns_topic_arn] # notify via SNS email when alarm fires

  ok_actions = [var.sns_topic_arn] # notify via SNS email when alarm recovers

  tags = {
    Name = "${var.name_prefix}-ec2-high-cpu"
  }
}


# ALARM 2 - ALB 5xx error
# Fires when ALB returns more than 5 server errors in a 5-minute window.
resource "aws_cloudwatch_metric_alarm" "alb_5xx_alarm" {
  alarm_name          = "${var.name_prefix}-alb-alarm"
  alarm_description   = "ALB 5xx errors above 5 in 5 minutes"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 5

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions      = [var.sns_topic_arn] # notify via SNS email when alarm fires
  treat_missing_data = "notBreaching"

  ok_actions = [var.sns_topic_arn] # notify via SNS email when alarm recovers

  tags = {
    Name = "${var.name_prefix}-alb-5xx-error"
  }
}


#ALARM - 3 DLQ MESSAGES
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${var.name_prefix}-dlq-messages"
  alarm_description   = "Messages in DLQ — booking notification failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0

  dimensions = {
    QueueName = var.dlq_name
  }

  alarm_actions      = [var.sns_topic_arn]
  treat_missing_data = "notBreaching"

  ok_actions = [var.sns_topic_arn]

  tags = {
    Name = "${var.name_prefix}-dlq-messages"
  }
}


#RDS HIGH CONNECTIONS

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${var.name_prefix}-rds-high-connections"
  alarm_description   = "RDS connections above 50 - possible connection leak"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 50

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_identifier
  }

  alarm_actions      = [var.sns_topic_arn]
  treat_missing_data = "notBreaching"

  tags = {
    Name = "${var.name_prefix}-rds-high-connections"
  }
}




# CLOUDWATCH DASHBOARD
# Live view of your entire system in one place.
# When something breaks at 2 AM come we come here
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "EC2 CPU Utilization"
          region = var.region
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.asg_name]
          ]
          period = 300
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB Request Count + 5XX Errors"
          region = var.region
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix]
          ]
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "RDS Connections"
          region = var.region
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.rds_instance_identifier]
          ]
          period = 300
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "SQS — Queue Depth + DLQ"
          region = var.region
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "${var.name_prefix}-booking-events"],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "${var.name_prefix}-booking-events-dlq"]
          ]
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
        }
      }
    ]
  })
}