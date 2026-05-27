#TRUST POLICY TO ATTACH TO EC2 ROLE
data "aws_iam_policy_document" "ec2_trust_policy" {
  statement {
    sid     = "AllowEC2ToAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}


# IAM ROLE
# Attaching trust policy on the role
resource "aws_iam_role" "ec2_role" {
  name = "${var.name_prefix}-ec2-role"

  assume_role_policy = data.aws_iam_policy_document.ec2_trust_policy.json
  tags = {
    Name = "${var.name_prefix}-ec2-role"
  }
}


# =============================================================================
# PERMISSIONS POLICY
# Least privilege — EC2 gets only what Flask actually needs.
# Every resource ARN is scoped to this project and environment.
# =============================================================================
data "aws_iam_policy_document" "ec2_permissions" {

  # --- Secrets Manager ---
  # Scoped to autoserve/dev/* only
  # EC2 fetches DB password at startup — never hardcoded anywhere
  statement {
    sid    = "SecretsManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      "arn:aws:secretsmanager:${var.region}:${var.aws_account_id}:secret:${var.project_name}/${var.environment}/*"
    ]
  }

  # --- SQS ---
  # Flask sends booking events, background worker reads and deletes them
  # Scoped to queues named autoserve-dev-* only
  statement {
    sid    = "SQSAccess"
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility"
    ]
    resources = [
      "arn:aws:sqs:${var.region}:${var.aws_account_id}:${var.project_name}-${var.environment}-*"
    ]
  }

  # --- CloudWatch Logs ---
  # Flask writes structured JSON logs here
  # Scoped to /autoserve/* log groups only
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = [
      "arn:aws:logs:${var.region}:${var.aws_account_id}:log-group:/${var.project_name}/*",
      "arn:aws:logs:${var.region}:${var.aws_account_id}:log-group:/${var.project_name}/*:*"
    ]
  }

  # --- CloudWatch Metrics ---
  # Publish custom metrics — booking rate, error count
  # PutMetricData does not support resource level restrictions so * is required
  statement {
    sid    = "CloudWatchMetrics"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData"
    ]
    resources = ["*"]
  }

  # --- SSM ---
  # Allows GitHub Actions to deploy code to EC2 without SSH keys
  # Standard SSM agent permission set — * required by AWS
  statement {
    sid    = "SSMAccess"
    effect = "Allow"
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply"
    ]
    resources = ["*"]
  }

  # --- SNS ---
  # Background worker publishes booking confirmation emails
  # Scoped to SNS topics named autoserve-dev-* only
  statement {
    sid    = "SNSPublish"
    effect = "Allow"
    actions = [
      "sns:Publish",
      "sns:GetTopicAttributes"
    ]
    resources = [
      "arn:aws:sns:${var.region}:${var.aws_account_id}:${var.project_name}-${var.environment}-*"
    ]
  }
}


# Attaching the permission to the role 
resource "aws_iam_role_policy" "ec2_policy" {
  name   = "${var.name_prefix}-ec2-policy"
  role   = aws_iam_role.ec2_role.id
  policy = data.aws_iam_policy_document.ec2_permissions.json
}


# INSTANCE PROFILE
# EC2 cannot use a role directly — needs this wrapper.
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}
