import json
import logging
import os
import urllib.error
import urllib.request
from typing import Any, Dict, Optional

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

secrets_client = boto3.client("secretsmanager")

SLACK_SECRET_NAME = os.environ.get("SLACK_WEBHOOK_SECRET_NAME")
SLACK_SECRET_KEY = os.environ.get("SLACK_WEBHOOK_SECRET_KEY", "slack_webhook_url")
DEFAULT_CHANNEL = os.environ.get("SLACK_CHANNEL", "")
SLACK_USERNAME = os.environ.get("SLACK_USERNAME", "DailyCoordinatorBot")
SLACK_ICON_EMOJI = os.environ.get("SLACK_ICON_EMOJI", ":spiral_calendar_pad:")
MESSAGE_PREFIX = os.environ.get("SLACK_MESSAGE_PREFIX", ":information_source: Task updated")

_cached_webhook: Optional[str] = None


def _load_webhook_url() -> str:
    """Retrieve and cache the Slack webhook URL from Secrets Manager."""
    global _cached_webhook

    if _cached_webhook:
        return _cached_webhook

    if not SLACK_SECRET_NAME:
        raise ValueError("SLACK_WEBHOOK_SECRET_NAME environment variable is not set")

    try:
        response = secrets_client.get_secret_value(SecretId=SLACK_SECRET_NAME)
    except Exception as exc:  # pragma: no cover - boto errors are logged
        logger.error("Unable to load Slack webhook secret: %s", exc)
        raise

    secret_string = response.get("SecretString")
    if not secret_string:
        raise ValueError("Slack webhook secret does not contain SecretString data")

    try:
        payload = json.loads(secret_string)
        if isinstance(payload, dict):
            webhook = payload.get(SLACK_SECRET_KEY) or payload.get("webhook_url")
        else:
            webhook = None
    except json.JSONDecodeError:
        webhook = secret_string

    if not webhook:
        raise ValueError("Slack webhook URL not found within the provided secret")

    _cached_webhook = webhook
    return webhook


def _extract_summary(event: Dict[str, Any]) -> Dict[str, Optional[str]]:
    """Build a concise summary from either direct invocation or SNS payloads."""
    summary: Dict[str, Optional[str]] = {
        "task": "Daily Coordinator",
        "status": "updated",
        "details": None,
        "subject": None,
    }

    if not isinstance(event, dict):
        return summary

    if "Records" in event:
        for record in event["Records"]:
            if record.get("EventSource") == "aws:sns":
                sns_payload = record.get("Sns", {})
                summary["subject"] = sns_payload.get("Subject")
                message = sns_payload.get("Message")
                summary["details"] = message

                if isinstance(message, str):
                    try:
                        decoded = json.loads(message)
                    except json.JSONDecodeError:
                        decoded = None

                    if isinstance(decoded, dict):
                        summary["task"] = decoded.get("task_name") or decoded.get("task") or summary["task"]
                        summary["status"] = decoded.get("status") or summary["status"]
                        summary["details"] = decoded.get("details") or decoded.get("message") or summary["details"]
                break
    else:
        summary["task"] = (
            event.get("task_name")
            or event.get("task")
            or event.get("coordinator_id")
            or summary["task"]
        )
        summary["status"] = event.get("status") or summary["status"]
        summary["details"] = event.get("details") or event.get("message") or summary["details"]

    return summary


def _render_message(summary: Dict[str, Optional[str]]) -> str:
    """Render the Slack message body from a summary dictionary."""
    lines = [MESSAGE_PREFIX]
    lines.append(f"*Task:* {summary['task']}")
    lines.append(f"*Status:* {summary['status']}")

    if summary.get("subject"):
        lines.append(f"*Subject:* {summary['subject']}")

    if summary.get("details"):
        lines.append(f"*Details:* {summary['details']}")

    return "\n".join(lines)


def _post_to_slack(webhook_url: str, payload: Dict[str, Any]) -> None:
    """Send a JSON payload to the Slack webhook."""
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        webhook_url,
        data=data,
        headers={"Content-Type": "application/json"},
    )

    try:
        with urllib.request.urlopen(request, timeout=5) as response:  # noqa: S310 bandit false positive
            logger.info("Slack response status: %s", response.status)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="ignore")
        logger.error("Slack webhook returned %s: %s", exc.code, body)
        raise
    except urllib.error.URLError as exc:
        logger.error("Unable to reach Slack webhook: %s", exc.reason)
        raise


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """AWS Lambda entrypoint for broadcasting task updates to Slack."""
    logger.info("Received event: %s", json.dumps(event, default=str))

    webhook_url = _load_webhook_url()
    summary = _extract_summary(event)
    message = _render_message(summary)

    payload: Dict[str, Any] = {"text": message}

    if SLACK_USERNAME:
        payload["username"] = SLACK_USERNAME

    if SLACK_ICON_EMOJI:
        payload["icon_emoji"] = SLACK_ICON_EMOJI

    if DEFAULT_CHANNEL:
        payload["channel"] = DEFAULT_CHANNEL

    _post_to_slack(webhook_url, payload)

    return {
        "statusCode": 200,
        "body": json.dumps(
            {
                "message": "Slack notification sent",
                "summary": summary,
            }
        ),
    }
