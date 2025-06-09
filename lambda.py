import boto3
import json
import time
import requests
from botocore.exceptions import ClientError
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Configuration
REGION = 'ap-south-1'
INSTANCE_ID = 'i-08ce9b2d7eccf6d26'  # Your GPU instance ID
MAX_WAIT_TIME = 300  # 5 minutes max wait for instance to start
FASTAPI_PORT = 8000

# Initialize AWS clients
ec2_client = boto3.client('ec2', region_name=REGION)
ec2_resource = boto3.resource('ec2', region_name=REGION)

def lambda_handler(event, context):
    """
    Main Lambda handler that can start/stop instances and trigger processing
    """
    try:
        action = event.get('action', 'start_and_process')
        
        if action == 'start':
            return start_gpu_instance(event, context)
        elif action == 'stop':
            return stop_gpu_instance(event, context)
        elif action == 'start_and_process':
            return start_instance_and_process(event, context)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': f'Unknown action: {action}'})
            }
            
    except Exception as e:
        logger.error(f"Lambda execution failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def start_gpu_instance(event, context):
    """Start the GPU instance"""
    try:
        response = ec2_client.start_instances(InstanceIds=[INSTANCE_ID])
        logger.info(f'Started GPU instance: {INSTANCE_ID}')
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Started GPU instance: {INSTANCE_ID}',
                'instance_id': INSTANCE_ID,
                'response': response
            })
        }
    except ClientError as e:
        logger.error(f'Failed to start instance: {e}')
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def stop_gpu_instance(event, context):
    """Stop the GPU instance"""
    try:
        response = ec2_client.stop_instances(InstanceIds=[INSTANCE_ID])
        logger.info(f'Stopped GPU instance: {INSTANCE_ID}')
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Stopped GPU instance: {INSTANCE_ID}',
                'instance_id': INSTANCE_ID,
                'response': response
            })
        }
    except ClientError as e:
        logger.error(f'Failed to stop instance: {e}')
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def start_instance_and_process(event, context):
    """Start instance, wait for it to be ready, then trigger FastAPI processing"""
    try:
        # Start the instance
        logger.info(f"Starting GPU instance: {INSTANCE_ID}")
        ec2_client.start_instances(InstanceIds=[INSTANCE_ID])
        
        # Wait for instance to be running and accessible
        instance_ip = wait_for_instance_ready()
        if not instance_ip:
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'Instance failed to start or become accessible'})
            }
        
        # Trigger FastAPI processing if payload provided
        processing_result = None
        if 'payload' in event:
            processing_result = trigger_fastapi_processing(instance_ip, event['payload'])
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'GPU instance started successfully',
                'instance_id': INSTANCE_ID,
                'instance_ip': instance_ip,
                'processing_result': processing_result
            })
        }
        
    except Exception as e:
        logger.error(f'Failed to start instance and process: {e}')
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def wait_for_instance_ready():
    """Wait for EC2 instance to be running and accessible"""
    instance = ec2_resource.Instance(INSTANCE_ID)
    
    # Wait for instance to be running
    logger.info("Waiting for instance to be in running state...")
    start_time = time.time()
    
    while time.time() - start_time < MAX_WAIT_TIME:
        try:
            instance.reload()
            if instance.state['Name'] == 'running':
                logger.info("Instance is running, getting IP address...")
                
                # Get public IP
                public_ip = instance.public_ip_address
                if public_ip:
                    logger.info(f"Instance public IP: {public_ip}")
                    
                    # Wait a bit more for the application to start
                    time.sleep(30)
                    
                    # Check if FastAPI is accessible
                    if check_fastapi_health(public_ip):
                        return public_ip
                        
            time.sleep(10)
            
        except Exception as e:
            logger.warning(f"Error checking instance status: {e}")
            time.sleep(10)
    
    logger.error("Instance failed to become ready within timeout")
    return None

def check_fastapi_health(instance_ip):
    """Check if FastAPI application is accessible"""
    try:
        health_url = f"http://{instance_ip}:{FASTAPI_PORT}/health"
        response = requests.get(health_url, timeout=10)
        
        if response.status_code == 200:
            logger.info("FastAPI application is healthy")
            return True
        else:
            logger.warning(f"FastAPI health check failed with status: {response.status_code}")
            return False
            
    except Exception as e:
        logger.warning(f"FastAPI health check failed: {e}")
        return False

def trigger_fastapi_processing(instance_ip, payload):
    """Trigger image processing on the FastAPI instance"""
    try:
        api_url = f"http://{instance_ip}:{FASTAPI_PORT}/upload-images/"
        
        # If payload contains file paths or URLs, process them
        if 'files' in payload:
            # Handle file upload processing
            response = requests.post(api_url, json=payload, timeout=300)
            
            if response.status_code == 200:
                result = response.json()
                logger.info(f"Processing completed successfully: {result}")
                return result
            else:
                logger.error(f"Processing failed with status {response.status_code}: {response.text}")
                return {'error': f'Processing failed: {response.text}'}
        
        return {'message': 'No files provided for processing'}
        
    except Exception as e:
        logger.error(f"Failed to trigger FastAPI processing: {e}")
        return {'error': str(e)}

# Legacy functions for backward compatibility
def gpu_inst_start(event, context):
    """Legacy function - use lambda_handler with action='start' instead"""
    return start_gpu_instance(event, context)

def gpu_inst_shut(event, context):
    """Legacy function - use lambda_handler with action='stop' instead"""
    return stop_gpu_instance(event, context)