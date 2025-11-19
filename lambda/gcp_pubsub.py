"""
GCP Pub/Sub publisher module for Lambda functions.
Publishes coordinator events to GCP Pub/Sub topic for downstream processing.
"""
import json
import logging
import os
from typing import Any, Dict

import boto3

try:
    from google.cloud import pubsub_v1  # type: ignore
    from google.oauth2 import service_account  # type: ignore
except ImportError:
    pubsub_v1 = None  # type: ignore
    service_account = None  # type: ignore

logger = logging.getLogger()
logger.setLevel(logging.INFO)

secrets_client = boto3.client("secretsmanager")

GCP_PUBSUB_SECRET_NAME = os.environ.get("GCP_PUBSUB_SECRET_NAME")
GCP_PROJECT_ID = os.environ.get("GCP_PROJECT_ID")
GCP_PUBSUB_TOPIC = os.environ.get("GCP_PUBSUB_TOPIC", "daily-coordinator-events")

_publisher_client = None


def _get_publisher_client():
    """Initialize and cache the GCP Pub/Sub publisher client."""
    global _publisher_client

    if _publisher_client:
        return _publisher_client

    if not pubsub_v1:
        raise ImportError(
            "google-cloud-pubsub library not available. "
            "Add it to Lambda layer or deployment package."
        )

    if not GCP_PUBSUB_SECRET_NAME:
        raise ValueError("GCP_PUBSUB_SECRET_NAME environment variable not set")

    if not GCP_PROJECT_ID:
        raise ValueError("GCP_PROJECT_ID environment variable not set")

    # Retrieve service account key from Secrets Manager
    try:
        response = secrets_client.get_secret_value(SecretId=GCP_PUBSUB_SECRET_NAME)
        key_json = response.get("SecretString")
        if not key_json:
            raise ValueError("GCP service account key not found in secret")

        credentials_info = json.loads(key_json)
        credentials = service_account.Credentials.from_service_account_info(
            credentials_info
        )

        _publisher_client = pubsub_v1.PublisherClient(credentials=credentials)
        logger.info("GCP Pub/Sub publisher client initialized")
        return _publisher_client

    except Exception as exc:
        logger.error("Failed to initialize GCP Pub/Sub client: %s", exc)
        raise


def publish_to_pubsub(event_data: Dict[str, Any]) -> str:
    """
    Publish event data to GCP Pub/Sub topic.

    Args:
        event_data: Dictionary containing event information to publish

    Returns:
        Message ID from Pub/Sub

    Raises:
        Exception: If publishing fails
    """
    try:
        client = _get_publisher_client()
        topic_path = client.topic_path(GCP_PROJECT_ID, GCP_PUBSUB_TOPIC)

        # Serialize event data to JSON bytes
        message_data = json.dumps(event_data).encode("utf-8")

        # Add attributes for filtering/routing
        attributes = {
            "source": "daily-coordinator",
            "event_type": event_data.get("status", "unknown"),
            "coordinator_id": event_data.get("coordinator_id", ""),
        }

        # Publish message
        future = client.publish(topic_path, message_data, **attributes)
        message_id = future.result(timeout=10)

        logger.info(
            "Published message %s to topic %s", message_id, GCP_PUBSUB_TOPIC
        )
        return message_id

    except Exception as exc:
        logger.error("Failed to publish to Pub/Sub: %s", exc)
        raise


def lambda_handler_with_pubsub(original_handler):
    """
    Decorator to wrap existing Lambda handlers with Pub/Sub publishing.

    Usage:
        @lambda_handler_with_pubsub
        def lambda_handler(event, context):
            # Your existing handler logic
            return results
    """

    def wrapper(event, context):
        # Call original handler
        result = original_handler(event, context)

        # Extract event data for publishing
        if isinstance(result, dict) and result.get("statusCode") == 200:
            try:
                body = json.loads(result.get("body", "{}"))
                publish_to_pubsub(body)
            except Exception as exc:
                logger.warning("Failed to publish to Pub/Sub: %s", exc)
                # Don't fail the Lambda if Pub/Sub publishing fails

        return result

    return wrapper
