"""
GCP Cloud Function to sync Pub/Sub events to Firestore.
Enables offline-first mobile access to coordinator task updates.
"""
import base64
import json
import logging
from datetime import datetime
from typing import Any, Dict

from google.cloud import firestore

logger = logging.getLogger(__name__)
db = firestore.Client()


def pubsub_to_firestore(event: Dict[str, Any], context: Any) -> None:
    """
    Cloud Function triggered by Pub/Sub message.
    Writes coordinator events to Firestore for offline mobile sync.

    Args:
        event: Pub/Sub message event
        context: Cloud Function context
    """
    try:
        # Decode Pub/Sub message
        if "data" in event:
            message_data = base64.b64decode(event["data"]).decode("utf-8")
            payload = json.loads(message_data)
        else:
            logger.warning("No data in Pub/Sub message")
            return

        # Extract attributes
        attributes = event.get("attributes", {})
        coordinator_id = payload.get("coordinator_id", "unknown")
        timestamp = payload.get("timestamp", datetime.utcnow().isoformat())

        # Prepare Firestore document
        task_doc = {
            "coordinator_id": coordinator_id,
            "status": payload.get("status", "unknown"),
            "tasks_processed": payload.get("tasks_processed", 0),
            "errors": payload.get("errors", []),
            "timestamp": timestamp,
            "event_type": attributes.get("event_type", "update"),
            "source": attributes.get("source", "pubsub"),
            "created_at": firestore.SERVER_TIMESTAMP,
            "synced": False,  # Mobile app marks True when synced offline
        }

        # Write to Firestore collection
        doc_id = f"{coordinator_id}_{int(datetime.utcnow().timestamp())}"
        db.collection("tasks").document(doc_id).set(task_doc)

        logger.info(f"Written to Firestore: {doc_id}")

        # Also update latest status in separate collection
        db.collection("coordinators").document(coordinator_id).set(
            {
                "last_status": payload.get("status"),
                "last_update": firestore.SERVER_TIMESTAMP,
                "total_tasks": firestore.Increment(
                    payload.get("tasks_processed", 0)
                ),
            },
            merge=True,
        )

    except Exception as exc:
        logger.error(f"Error processing Pub/Sub message: {exc}")
        raise
