"""
WhatsApp alert sender for Daily Coordinator.
Sends high-priority task updates via Twilio WhatsApp Business API.
"""
import json
import logging
import os
from typing import Any, Dict

import boto3

try:
    from twilio.rest import Client  # type: ignore
except ImportError:
    Client = None  # type: ignore

logger = logging.getLogger()
logger.setLevel(logging.INFO)

secrets_client = boto3.client("secretsmanager")

TWILIO_SECRET_NAME = os.environ.get("TWILIO_SECRET_NAME")
WHATSAPP_FROM = os.environ.get("WHATSAPP_FROM", "whatsapp:+14155238886")
WHATSAPP_TO = os.environ.get("WHATSAPP_TO")  # Comma-separated numbers

_twilio_client = None


def _get_twilio_client():
    """Initialize and cache Twilio client with credentials from Secrets Manager."""
    global _twilio_client

    if _twilio_client:
        return _twilio_client

    if not Client:
        raise ImportError(
            "twilio library not available. Add to Lambda layer or deployment package."
        )

    if not TWILIO_SECRET_NAME:
        raise ValueError("TWILIO_SECRET_NAME environment variable not set")

    try:
        response = secrets_client.get_secret_value(SecretId=TWILIO_SECRET_NAME)
        secret_string = response.get("SecretString")
        if not secret_string:
            raise ValueError("Twilio credentials not found in secret")

        creds = json.loads(secret_string)
        account_sid = creds.get("account_sid")
        auth_token = creds.get("auth_token")

        if not account_sid or not auth_token:
            raise ValueError("Missing account_sid or auth_token in secret")

        _twilio_client = Client(account_sid, auth_token)
        logger.info("Twilio client initialized")
        return _twilio_client

    except Exception as exc:
        logger.error(f"Failed to initialize Twilio client: {exc}")
        raise


def _format_whatsapp_message(event_data: Dict[str, Any]) -> str:
    """Format coordinator event data for WhatsApp message."""
    coordinator_id = event_data.get("coordinator_id", "Unknown")
    status = event_data.get("status", "unknown")
    tasks_processed = event_data.get("tasks_processed", 0)
    errors = event_data.get("errors", [])
    timestamp = event_data.get("timestamp", "")

    # Status emoji
    status_emoji = {
        "success": "✅",
        "failed": "❌",
        "partial": "⚠️",
    }.get(status, "ℹ️")

    # Build message
    lines = [
        f"{status_emoji} *Daily Coordinator Update*",
        f"",
        f"*ID:* {coordinator_id}",
        f"*Status:* {status.upper()}",
        f"*Tasks:* {tasks_processed}",
    ]

    if errors:
        lines.append(f"*Errors:* {len(errors)}")
        if len(errors) <= 3:
            for err in errors:
                lines.append(f"  • {err}")

    if timestamp:
        lines.append(f"*Time:* {timestamp}")

    return "\n".join(lines)


def send_whatsapp_alert(event_data: Dict[str, Any], recipient: str) -> str:
    """
    Send WhatsApp message via Twilio.

    Args:
        event_data: Coordinator event data
        recipient: WhatsApp number in format 'whatsapp:+1234567890'

    Returns:
        Message SID from Twilio

    Raises:
        Exception: If sending fails
    """
    try:
        client = _get_twilio_client()
        message_body = _format_whatsapp_message(event_data)

        message = client.messages.create(
            from_=WHATSAPP_FROM, to=recipient, body=message_body
        )

        logger.info(f"WhatsApp sent to {recipient}, SID: {message.sid}")
        return message.sid

    except Exception as exc:
        logger.error(f"Failed to send WhatsApp to {recipient}: {exc}")
        raise


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for WhatsApp alerts.
    Triggered by SNS topic subscription for high-priority events.

    Args:
        event: Lambda event (SNS or direct invocation)
        context: Lambda context

    Returns:
        Response dict with status and message SIDs
    """
    logger.info(f"Received event: {json.dumps(event, default=str)}")

    # Extract event data from SNS or direct payload
    if "Records" in event:
        # SNS trigger
        event_data = None
        for record in event["Records"]:
            if record.get("EventSource") == "aws:sns":
                sns_message = record["Sns"]["Message"]
                try:
                    event_data = json.loads(sns_message)
                except json.JSONDecodeError:
                    event_data = {"message": sns_message}
                break
    else:
        # Direct invocation
        event_data = event

    if not event_data:
        return {"statusCode": 400, "body": json.dumps({"error": "No event data"})}

    # Get recipient numbers
    if not WHATSAPP_TO:
        logger.warning("WHATSAPP_TO not configured, skipping WhatsApp alerts")
        return {
            "statusCode": 200,
            "body": json.dumps({"message": "WhatsApp not configured"}),
        }

    recipients = [num.strip() for num in WHATSAPP_TO.split(",")]
    results = []

    # Send to all recipients
    for recipient in recipients:
        # Ensure proper WhatsApp format
        if not recipient.startswith("whatsapp:"):
            recipient = f"whatsapp:{recipient}"

        try:
            message_sid = send_whatsapp_alert(event_data, recipient)
            results.append({"recipient": recipient, "sid": message_sid, "status": "sent"})
        except Exception as exc:
            results.append(
                {"recipient": recipient, "error": str(exc), "status": "failed"}
            )

    return {
        "statusCode": 200,
        "body": json.dumps(
            {"message": "WhatsApp alerts processed", "results": results}
        ),
    }
