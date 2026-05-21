# AutoServe Pro — Vehicle Service Booking System

A production-level AWS cloud application built with Terraform and deployed via GitHub Actions CI/CD.

## What it does
Customers book vehicle service appointments online, receive email confirmations,
and can view their booking history. Admins manage all bookings from a dashboard.

## Architecture
| Layer | Services |
|---|---|
| Auth | AWS Cognito |
| DNS + CDN | Route 53, CloudFront, WAF |
| Frontend | S3 |
| Compute | ALB, Auto Scaling Group, EC2 (Python Flask) |
| Data | RDS MySQL 8.0, ElastiCache Redis |
| Messaging | SQS, SNS |
| Security | IAM, Secrets Manager |
| Observability | CloudWatch |
| CI/CD | GitHub Actions |

## Region
`ca-central-1` — Toronto, Canada

## Infrastructure
All infrastructure is written in Terraform using a modular structure.
No resources are created manually in the AWS console.