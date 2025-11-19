import json
import os
import boto3
import logging
from datetime import datetime
from typing import Dict, Any

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
s3_client = boto3.client('s3')
sns_client = boto3.client('sns')
secrets_client = boto3.client('secretsmanager')

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment variables
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE')
S3_BUCKET = os.environ.get('S3_BUCKET')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')
SECRETS_MANAGER_ARN = os.environ.get('SECRETS_MANAGER_ARN')


def get_secrets() -> Dict[str, Any]:
    """
    Retrieve secrets from AWS Secrets Manager.
    
    Returns:
        Dict containing secret key-value pairs
    """
    try:
        secret_name = SECRETS_MANAGER_ARN.split(':')[-1]
        response = secrets_client.get_secret_value(SecretId=secret_name)
        
        if 'SecretString' in response:
            return json.loads(response['SecretString'])
        else:
            logger.warning("Secrets not found in Secrets Manager")
            return {}
    except Exception as e:
        logger.error(f"Error retrieving secrets: {str(e)}")
        return {}


def save_state_to_dynamodb(coordinator_id: str, state: Dict[str, Any]) -> bool:
    """
    Save coordinator state to DynamoDB.
    
    Args:
        coordinator_id: Unique identifier for the coordinator
        state: Dictionary containing state information
        
    Returns:
        True if successful, False otherwise
    """
    try:
        table = dynamodb.Table(DYNAMODB_TABLE)
        
        item = {
            'coordinator_id': coordinator_id,
            'timestamp': int(datetime.utcnow().timestamp() * 1000),
            'status': state.get('status', 'pending'),
            'data': json.dumps(state),
            'updated_at': datetime.utcnow().isoformat()
        }
        
        table.put_item(Item=item)
        logger.info(f"State saved for coordinator {coordinator_id}")
        return True
    except Exception as e:
        logger.error(f"Error saving state to DynamoDB: {str(e)}")
        return False


def upload_cache_to_s3(key: str, data: Dict[str, Any]) -> bool:
    """
    Upload cache data to S3 bucket.
    
    Args:
        key: S3 object key/path
        data: Dictionary to upload as JSON
        
    Returns:
        True if successful, False otherwise
    """
    try:
        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=key,
            Body=json.dumps(data),
            ContentType='application/json',
            ServerSideEncryption='AES256'
        )
        logger.info(f"Cache uploaded to S3: {key}")
        return True
    except Exception as e:
        logger.error(f"Error uploading to S3: {str(e)}")
        return False


def publish_alert(subject: str, message: str) -> bool:
    """
    Publish alert to SNS topic.
    
    Args:
        subject: Alert subject
        message: Alert message
        
    Returns:
        True if successful, False otherwise
    """
    try:
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message
        )
        logger.info(f"Alert published: {subject}")
        return True
    except Exception as e:
        logger.error(f"Error publishing alert: {str(e)}")
        return False


def coordinate_daily_tasks() -> Dict[str, Any]:
    """
    Main coordination logic for daily tasks.
    
    Returns:
        Dictionary with coordination results
    """
    coordinator_id = "daily-coordinator-001"
    timestamp = datetime.utcnow().isoformat()
    
    results = {
        'coordinator_id': coordinator_id,
        'timestamp': timestamp,
        'status': 'success',
        'tasks_processed': 0,
        'errors': []
    }
    
    try:
        # Retrieve secrets if needed
        secrets = get_secrets()
        logger.info("Secrets retrieved successfully")
        
        # Example: Save state
        state_data = {
            'status': 'running',
            'last_run': timestamp,
            'tasks_count': 5
        }
        
        if save_state_to_dynamodb(coordinator_id, state_data):
            results['tasks_processed'] += 1
        else:
            results['errors'].append('Failed to save state to DynamoDB')
        
        # Example: Upload cache
        cache_data = {
            'timestamp': timestamp,
            'coordinator_id': coordinator_id,
            'cache_entries': 10,
            'status': 'cached'
        }
        
        cache_key = f"cache/{coordinator_id}/{datetime.utcnow().date()}.json"
        if upload_cache_to_s3(cache_key, cache_data):
            results['tasks_processed'] += 1
        else:
            results['errors'].append('Failed to upload cache to S3')
        
        # Update final state
        state_data['status'] = 'completed'
        save_state_to_dynamodb(coordinator_id, state_data)
        
        # Publish success alert if there are errors
        if results['errors']:
            alert_message = f"Daily Coordinator completed with {len(results['errors'])} errors:\n"
            alert_message += "\n".join(results['errors'])
            publish_alert("Daily Coordinator - Partial Success", alert_message)
        else:
            publish_alert(
                "Daily Coordinator - Success",
                f"Daily coordination completed successfully at {timestamp}"
            )
        
        return results
        
    except Exception as e:
        logger.error(f"Error in coordinate_daily_tasks: {str(e)}")
        results['status'] = 'failed'
        results['errors'].append(str(e))
        publish_alert("Daily Coordinator - Failed", f"Error: {str(e)}")
        return results


def lambda_handler(event, context):
    """
    Lambda handler for Daily Coordinator agent.
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Dictionary with status and results
    """
    logger.info(f"Received event: {json.dumps(event)}")
    
    try:
        # Execute coordination
        results = coordinate_daily_tasks()
        
        return {
            'statusCode': 200,
            'body': json.dumps(results)
        }
    except Exception as e:
        logger.error(f"Lambda handler error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }
