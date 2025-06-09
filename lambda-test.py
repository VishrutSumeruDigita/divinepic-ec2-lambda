import boto3
import json
import time
import requests
from botocore.exceptions import ClientError
import logging
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Configuration for TEST environment
REGION = os.getenv('AWS_REGION', 'ap-south-1')
INSTANCE_ID = os.getenv('TEST_INSTANCE_ID')  # Read from environment variable
if not INSTANCE_ID:
    raise ValueError("TEST_INSTANCE_ID environment variable is required")
MAX_WAIT_TIME = 300  # 5 minutes max wait for instance to start
FASTAPI_PORT = 8000
ENVIRONMENT = 'test'

# Initialize AWS clients
ec2_client = boto3.client('ec2', region_name=REGION)
ec2_resource = boto3.resource('ec2', region_name=REGION)

def lambda_handler(event, context):
    """
    Test Lambda handler for CPU-based development environment
    """
    try:
        action = event.get('action', 'start_and_process')
        
        logger.info(f"TEST Environment - Processing action: {action}")
        
        if action == 'start':
            return start_test_instance(event, context)
        elif action == 'stop':
            return stop_test_instance(event, context)
        elif action == 'start_and_process':
            return start_instance_and_process(event, context)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': f'Unknown action: {action}', 'environment': ENVIRONMENT})
            }
            
    except Exception as e:
        logger.error(f"TEST Lambda execution failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e), 'environment': ENVIRONMENT})
        }

def start_test_instance(event, context):
    """Start the CPU test instance"""
    try:
        response = ec2_client.start_instances(InstanceIds=[INSTANCE_ID])
        logger.info(f'Started TEST CPU instance: {INSTANCE_ID}')
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Started TEST CPU instance: {INSTANCE_ID}',
                'instance_id': INSTANCE_ID,
                'environment': ENVIRONMENT,
                'instance_type': 'CPU',
                'response': response
            })
        }
    except ClientError as e:
        logger.error(f'Failed to start TEST instance: {e}')
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e), 'environment': ENVIRONMENT})
        }

def stop_test_instance(event, context):
    """Stop the CPU test instance"""
    try:
        response = ec2_client.stop_instances(InstanceIds=[INSTANCE_ID])
        logger.info(f'Stopped TEST CPU instance: {INSTANCE_ID}')
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Stopped TEST CPU instance: {INSTANCE_ID}',
                'instance_id': INSTANCE_ID,
                'environment': ENVIRONMENT,
                'instance_type': 'CPU',
                'response': response
            })
        }
    except ClientError as e:
        logger.error(f'Failed to stop TEST instance: {e}')
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e), 'environment': ENVIRONMENT})
        }

def start_instance_and_process(event, context):
    """Start test instance, wait for it to be ready, then trigger FastAPI processing"""
    try:
        # Start the instance
        logger.info(f"Starting TEST CPU instance: {INSTANCE_ID}")
        ec2_client.start_instances(InstanceIds=[INSTANCE_ID])
        
        # Wait for instance to be running and accessible
        instance_ip = wait_for_instance_ready()
        if not instance_ip:
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'error': 'TEST instance failed to start or become accessible',
                    'environment': ENVIRONMENT
                })
            }
        
        # Trigger FastAPI processing if payload provided
        processing_result = None
        if 'payload' in event:
            processing_result = trigger_fastapi_processing(instance_ip, event['payload'])
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'TEST CPU instance started successfully',
                'instance_id': INSTANCE_ID,
                'instance_ip': instance_ip,
                'environment': ENVIRONMENT,
                'instance_type': 'CPU',
                'processing_result': processing_result
            })
        }
        
    except Exception as e:
        logger.error(f'Failed to start TEST instance and process: {e}')
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e), 'environment': ENVIRONMENT})
        }

def wait_for_instance_ready():
    """Wait for EC2 test instance to be running and accessible"""
    instance = ec2_resource.Instance(INSTANCE_ID)
    
    # Wait for instance to be running
    logger.info("Waiting for TEST instance to be in running state...")
    start_time = time.time()
    
    while time.time() - start_time < MAX_WAIT_TIME:
        try:
            instance.reload()
            if instance.state['Name'] == 'running':
                logger.info("TEST instance is running, getting IP address...")
                
                # Get public IP
                public_ip = instance.public_ip_address
                if public_ip:
                    logger.info(f"TEST instance public IP: {public_ip}")
                    
                    # Wait a bit more for the application to start (CPU instances need more time)
                    time.sleep(45)  # CPU instances typically need more startup time
                    
                    # Check if FastAPI is accessible
                    if check_fastapi_health(public_ip):
                        return public_ip
                        
            time.sleep(10)
            
        except Exception as e:
            logger.warning(f"Error checking TEST instance status: {e}")
            time.sleep(10)
    
    logger.error("TEST instance failed to become ready within timeout")
    return None

def check_fastapi_health(instance_ip):
    """Check if FastAPI application is accessible on test instance"""
    try:
        health_url = f"http://{instance_ip}:{FASTAPI_PORT}/health"
        response = requests.get(health_url, timeout=15)
        
        if response.status_code == 200:
            result = response.json()
            logger.info(f"TEST FastAPI application is healthy: {result}")
            return True
        else:
            logger.warning(f"TEST FastAPI health check failed with status: {response.status_code}")
            return False
            
    except Exception as e:
        logger.warning(f"TEST FastAPI health check failed: {e}")
        return False

def trigger_fastapi_processing(instance_ip, payload):
    """Trigger image processing on the test FastAPI instance"""
    try:
        api_url = f"http://{instance_ip}:{FASTAPI_PORT}/upload-images/"
        
        # Add environment flag to payload
        payload['environment'] = ENVIRONMENT
        payload['instance_type'] = 'CPU'
        
        # If payload contains file paths or URLs, process them
        if 'files' in payload:
            # Handle file upload processing
            response = requests.post(api_url, json=payload, timeout=600)  # Longer timeout for CPU processing
            
            if response.status_code == 200:
                result = response.json()
                logger.info(f"TEST processing completed successfully: {result}")
                return result
            else:
                logger.error(f"TEST processing failed with status {response.status_code}: {response.text}")
                return {'error': f'TEST processing failed: {response.text}'}
        
        return {'message': 'No files provided for TEST processing'}
        
    except Exception as e:
        logger.error(f"Failed to trigger TEST FastAPI processing: {e}")
        return {'error': str(e)}

# Legacy functions for backward compatibility
def test_inst_start(event, context):
    """Legacy function - use lambda_handler with action='start' instead"""
    return start_test_instance(event, context)

def test_inst_stop(event, context):
    """Legacy function - use lambda_handler with action='stop' instead"""
    return stop_test_instance(event, context) 