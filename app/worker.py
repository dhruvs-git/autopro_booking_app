import os
import json
import time
import logging
import boto3
from botocore.exceptions import ClientError

logging.basicConfig(
    level=logging.INFO,
    format='{"time": "%(asctime)s", "level": "%(levelname)s", "message": "%(message)s"}'
)
logger = logging.getLogger(__name__)

AWS_REGION    = os.environ["AWS_REGION"]
SQS_QUEUE_URL = os.environ["SQS_QUEUE_URL"]
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]

sqs = boto3.client("sqs", region_name=AWS_REGION)
sns = boto3.client("sns", region_name=AWS_REGION)


def format_email(booking):
    return f"""
Your booking has been confirmed!

Booking ID:  SVC-{booking['booking_id']}
Vehicle:     {booking['vehicle']}
Service:     {booking['service']}
Date:        {booking['date']}
Time:        {booking['time_slot']}

Thank you for choosing AutoServe Pro.
We look forward to serving you.

AutoServe Pro Team
    """.strip()


def process_message(message):
    try:
        booking = json.loads(message["Body"])

        logger.info(f"Processing booking {booking.get('booking_id')} for {booking.get('user_email')}")

        sns.publish(
            TopicArn = SNS_TOPIC_ARN,
            Subject  = f"AutoServe Pro - Booking Confirmed (SVC-{booking['booking_id']})",
            Message  = format_email(booking)
        )

        logger.info(f"Notification sent for booking {booking.get('booking_id')}")
        return True

    except ClientError as e:
        logger.error(f"AWS error processing message: {str(e)}")
        return False

    except Exception as e:
        logger.error(f"Unexpected error processing message: {str(e)}")
        return False


def delete_message(receipt_handle):
    try:
        sqs.delete_message(
            QueueUrl      = SQS_QUEUE_URL,
            ReceiptHandle = receipt_handle
        )
        logger.info("Message deleted from queue")
    except ClientError as e:
        logger.error(f"Failed to delete message: {str(e)}")


def main():
    logger.info("AutoServe worker starting — polling SQS")

    while True:
        try:
            response = sqs.receive_message(
                QueueUrl            = SQS_QUEUE_URL,
                MaxNumberOfMessages = 10,
                WaitTimeSeconds     = 10,
                VisibilityTimeout   = 30
            )

            messages = response.get("Messages", [])

            if not messages:
                logger.info("No messages — waiting")
                continue

            for message in messages:
                success = process_message(message)

                if success:
                    delete_message(message["ReceiptHandle"])
                else:
                    logger.warning(
                        f"Message processing failed — leaving in queue for retry. "
                        f"Receipt: {message['ReceiptHandle'][:20]}..."
                    )

        except ClientError as e:
            logger.error(f"SQS poll error: {str(e)}")
            time.sleep(5)

        except Exception as e:
            logger.error(f"Unexpected worker error: {str(e)}")
            time.sleep(5)


if __name__ == "__main__":
    main()
