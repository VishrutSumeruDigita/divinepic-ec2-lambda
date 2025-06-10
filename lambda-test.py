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
S3_BUCKET = 'divinepic-test'

# Initialize AWS clients
ec2_client = boto3.client('ec2', region_name=REGION)
ec2_resource = boto3.resource('ec2', region_name=REGION)
ssm_client = boto3.client('ssm', region_name=REGION)

def lambda_handler(event, context):
    """
    Test Lambda handler for CPU-based development environment
    """
    try:
        action = event.get('action', 'deploy_and_start')
        
        logger.info(f"TEST Environment - Processing action: {action}")
        
        if action == 'start':
            return start_test_instance(event, context)
        elif action == 'stop':
            return stop_test_instance(event, context)
        elif action == 'start_and_process':
            return start_instance_and_process(event, context)
        elif action == 'deploy_and_start':
            return deploy_and_start_application(event, context)
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

def deploy_and_start_application(event, context):
    """Deploy code from S3 and start FastAPI application on the test instance"""
    try:
        # Start the instance
        logger.info(f"Starting TEST CPU instance: {INSTANCE_ID}")
        ec2_client.start_instances(InstanceIds=[INSTANCE_ID])
        
        # Wait for instance to be running and SSM ready
        instance_ip = wait_for_instance_running()
        if not instance_ip:
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'error': 'TEST instance failed to start',
                    'environment': ENVIRONMENT
                })
            }
        
        # Deploy application via SSM
        deployment_result = deploy_application_via_ssm()
        
        # Wait for FastAPI to be ready
        time.sleep(30)  # Give the app time to start
        
        # Check if FastAPI is accessible
        if check_fastapi_health(instance_ip):
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'TEST application deployed and started successfully',
                    'instance_id': INSTANCE_ID,
                    'instance_ip': instance_ip,
                    'environment': ENVIRONMENT,
                    'instance_type': 'CPU',
                    'fastapi_url': f'http://{instance_ip}:{FASTAPI_PORT}/docs',
                    'deployment_result': deployment_result
                })
            }
        else:
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'error': 'Application deployed but FastAPI not responding',
                    'instance_id': INSTANCE_ID,
                    'instance_ip': instance_ip,
                    'environment': ENVIRONMENT,
                    'deployment_result': deployment_result
                })
            }
        
    except Exception as e:
        logger.error(f'Failed to deploy and start TEST application: {e}')
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e), 'environment': ENVIRONMENT})
        }

def deploy_application_via_ssm():
    """Deploy application code via SSM Run Command"""
    try:
        logger.info("Deploying TEST application via SSM...")
        
        # Commands to deploy and start the application
        commands = [
            "#!/bin/bash",
            "cd /home/ubuntu",
            "rm -rf divinepic-ec2-lambda",
            "mkdir -p divinepic-ec2-lambda",
            "cd divinepic-ec2-lambda",
            f"aws s3 sync s3://{S3_BUCKET}/app-files/test/ . --region {REGION}",
            "sudo apt update",
            "sudo apt install -y python3-pip",
            "pip3 install -r requirements.test.txt",
            "# Kill any existing FastAPI processes",
            "pkill -f uvicorn || true",
            "# Start FastAPI in background",
            "nohup python3 -m uvicorn app:app --host 0.0.0.0 --port 8000 > fastapi.log 2>&1 &",
            "sleep 5",
            "echo 'Deployment completed'"
        ]
        
        # Execute commands via SSM
        response = ssm_client.send_command(
            InstanceIds=[INSTANCE_ID],
            DocumentName="AWS-RunShellScript",
            Parameters={'commands': commands},
            TimeoutSeconds=300
        )
        
        command_id = response['Command']['CommandId']
        logger.info(f"SSM command executed with ID: {command_id}")
        
        # Wait for command to complete
        time.sleep(60)  # Give it time to run
        
        # Get command output
        try:
            output = ssm_client.get_command_invocation(
                CommandId=command_id,
                InstanceId=INSTANCE_ID
            )
            logger.info(f"SSM command output: {output.get('StandardOutputContent', '')}")
            return {
                'command_id': command_id,
                'status': output.get('Status', 'Unknown'),
                'output': output.get('StandardOutputContent', ''),
                'error': output.get('StandardErrorContent', '')
            }
        except Exception as e:
            logger.warning(f"Could not get SSM command output: {e}")
            return {'command_id': command_id, 'status': 'Completed'}
        
    except Exception as e:
        logger.error(f"Failed to deploy via SSM: {e}")
        return {'error': str(e)}

def wait_for_instance_running():
    """Wait for EC2 instance to be running"""
    instance = ec2_resource.Instance(INSTANCE_ID)
    
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
                    # Wait for SSM agent to be ready
                    time.sleep(30)
                    return public_ip
                        
            time.sleep(10)
            
        except Exception as e:
            logger.warning(f"Error checking TEST instance status: {e}")
            time.sleep(10)
    
    logger.error("TEST instance failed to become ready within timeout")
    return None

# Legacy functions for backward compatibility
def test_inst_start(event, context):
    """Legacy function - use lambda_handler with action='start' instead"""
    return start_test_instance(event, context)

def test_inst_stop(event, context):
    """Legacy function - use lambda_handler with action='stop' instead"""
    return stop_test_instance(event, context) 