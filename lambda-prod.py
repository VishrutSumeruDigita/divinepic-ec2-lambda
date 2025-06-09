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

# Configuration for PRODUCTION environment
REGION = os.getenv('AWS_REGION', 'ap-south-1')
INSTANCE_ID = os.getenv('PROD_INSTANCE_ID')  # Read from environment variable
if not INSTANCE_ID:
    raise ValueError("PROD_INSTANCE_ID environment variable is required")
MAX_WAIT_TIME = 300  # 5 minutes max wait for instance to start
FASTAPI_PORT = 8000
ENVIRONMENT = 'production'

# Initialize AWS clients
ec2_client = boto3.client('ec2', region_name=REGION)
ec2_resource = boto3.resource('ec2', region_name=REGION)

def lambda_handler(event, context):
    """
    Production Lambda handler for GPU-based high-performance environment
    """
    try:
        action = event.get('action', 'start_and_process')
        
        logger.info(f"PRODUCTION Environment - Processing action: {action}")
        
        if action == 'start':
            return start_gpu_instance(event, context)
        elif action == 'stop':
            return stop_gpu_instance(event, context)
        elif action == 'start_and_process':
            return start_instance_and_process(event, context)
        elif action == 'scale_up':
            return scale_up_instances(event, context)
        elif action == 'scale_down':
            return scale_down_instances(event, context)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': f'Unknown action: {action}', 'environment': ENVIRONMENT})
            }
            
    except Exception as e:
        logger.error(f"PRODUCTION Lambda execution failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e), 'environment': ENVIRONMENT})
        }

def start_gpu_instance(event, context):
    """Start the GPU production instance"""
    try:
        response = ec2_client.start_instances(InstanceIds=[INSTANCE_ID])
        logger.info(f'Started PRODUCTION GPU instance: {INSTANCE_ID}')
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Started PRODUCTION GPU instance: {INSTANCE_ID}',
                'instance_id': INSTANCE_ID,
                'environment': ENVIRONMENT,
                'instance_type': 'GPU',
                'response': response
            })
        }
    except ClientError as e:
        logger.error(f'Failed to start PRODUCTION instance: {e}')
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e), 'environment': ENVIRONMENT})
        }

def stop_gpu_instance(event, context):
    """Stop the GPU production instance"""
    try:
        response = ec2_client.stop_instances(InstanceIds=[INSTANCE_ID])
        logger.info(f'Stopped PRODUCTION GPU instance: {INSTANCE_ID}')
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Stopped PRODUCTION GPU instance: {INSTANCE_ID}',
                'instance_id': INSTANCE_ID,
                'environment': ENVIRONMENT,
                'instance_type': 'GPU',
                'response': response
            })
        }
    except ClientError as e:
        logger.error(f'Failed to stop PRODUCTION instance: {e}')
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e), 'environment': ENVIRONMENT})
        }

def start_instance_and_process(event, context):
    """Start production instance, wait for it to be ready, then trigger FastAPI processing"""
    try:
        # Start the instance
        logger.info(f"Starting PRODUCTION GPU instance: {INSTANCE_ID}")
        ec2_client.start_instances(InstanceIds=[INSTANCE_ID])
        
        # Wait for instance to be running and accessible
        instance_ip = wait_for_instance_ready()
        if not instance_ip:
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'error': 'PRODUCTION instance failed to start or become accessible',
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
                'message': 'PRODUCTION GPU instance started successfully',
                'instance_id': INSTANCE_ID,
                'instance_ip': instance_ip,
                'environment': ENVIRONMENT,
                'instance_type': 'GPU',
                'processing_result': processing_result
            })
        }
        
    except Exception as e:
        logger.error(f'Failed to start PRODUCTION instance and process: {e}')
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e), 'environment': ENVIRONMENT})
        }

def wait_for_instance_ready():
    """Wait for EC2 production instance to be running and accessible"""
    instance = ec2_resource.Instance(INSTANCE_ID)
    
    # Wait for instance to be running
    logger.info("Waiting for PRODUCTION instance to be in running state...")
    start_time = time.time()
    
    while time.time() - start_time < MAX_WAIT_TIME:
        try:
            instance.reload()
            if instance.state['Name'] == 'running':
                logger.info("PRODUCTION instance is running, getting IP address...")
                
                # Get public IP
                public_ip = instance.public_ip_address
                if public_ip:
                    logger.info(f"PRODUCTION instance public IP: {public_ip}")
                    
                    # Wait for GPU initialization and application startup
                    time.sleep(60)  # GPU instances need more time for driver initialization
                    
                    # Check if FastAPI is accessible
                    if check_fastapi_health(public_ip):
                        return public_ip
                        
            time.sleep(10)
            
        except Exception as e:
            logger.warning(f"Error checking PRODUCTION instance status: {e}")
            time.sleep(10)
    
    logger.error("PRODUCTION instance failed to become ready within timeout")
    return None

def check_fastapi_health(instance_ip):
    """Check if FastAPI application is accessible on production instance"""
    try:
        health_url = f"http://{instance_ip}:{FASTAPI_PORT}/health"
        response = requests.get(health_url, timeout=20)
        
        if response.status_code == 200:
            result = response.json()
            logger.info(f"PRODUCTION FastAPI application is healthy: {result}")
            
            # Additional GPU health check
            gpu_status = check_gpu_status(instance_ip)
            logger.info(f"PRODUCTION GPU status: {gpu_status}")
            
            return True
        else:
            logger.warning(f"PRODUCTION FastAPI health check failed with status: {response.status_code}")
            return False
            
    except Exception as e:
        logger.warning(f"PRODUCTION FastAPI health check failed: {e}")
        return False

def check_gpu_status(instance_ip):
    """Check GPU status on production instance"""
    try:
        gpu_url = f"http://{instance_ip}:{FASTAPI_PORT}/gpu-status"
        response = requests.get(gpu_url, timeout=10)
        
        if response.status_code == 200:
            return response.json()
        else:
            return {"error": "GPU status check failed", "status_code": response.status_code}
            
    except Exception as e:
        return {"error": str(e)}

def trigger_fastapi_processing(instance_ip, payload):
    """Trigger image processing on the production FastAPI instance"""
    try:
        api_url = f"http://{instance_ip}:{FASTAPI_PORT}/upload-images/"
        
        # Add environment flag to payload
        payload['environment'] = ENVIRONMENT
        payload['instance_type'] = 'GPU'
        payload['priority'] = 'high'  # Production priority
        
        # If payload contains file paths or URLs, process them
        if 'files' in payload:
            # Handle file upload processing
            response = requests.post(api_url, json=payload, timeout=900)  # 15 minutes for large batches
            
            if response.status_code == 200:
                result = response.json()
                logger.info(f"PRODUCTION processing completed successfully: {result}")
                return result
            else:
                logger.error(f"PRODUCTION processing failed with status {response.status_code}: {response.text}")
                return {'error': f'PRODUCTION processing failed: {response.text}'}
        
        return {'message': 'No files provided for PRODUCTION processing'}
        
    except Exception as e:
        logger.error(f"Failed to trigger PRODUCTION FastAPI processing: {e}")
        return {'error': str(e)}

def scale_up_instances(event, context):
    """Scale up additional GPU instances for high load (future enhancement)"""
    try:
        logger.info("PRODUCTION scale-up requested")
        # This would handle launching additional instances
        # For now, just return success
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Scale-up functionality not yet implemented',
                'environment': ENVIRONMENT,
                'action': 'scale_up'
            })
        }
    except Exception as e:
        logger.error(f'Failed to scale up PRODUCTION instances: {e}')
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e), 'environment': ENVIRONMENT})
        }

def scale_down_instances(event, context):
    """Scale down GPU instances after processing (future enhancement)"""
    try:
        logger.info("PRODUCTION scale-down requested")
        # This would handle terminating additional instances
        # For now, just return success
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Scale-down functionality not yet implemented',
                'environment': ENVIRONMENT,
                'action': 'scale_down'
            })
        }
    except Exception as e:
        logger.error(f'Failed to scale down PRODUCTION instances: {e}')
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e), 'environment': ENVIRONMENT})
        }

# Legacy functions for backward compatibility
def gpu_inst_start(event, context):
    """Legacy function - use lambda_handler with action='start' instead"""
    return start_gpu_instance(event, context)

def gpu_inst_shut(event, context):
    """Legacy function - use lambda_handler with action='stop' instead"""
    return stop_gpu_instance(event, context) 