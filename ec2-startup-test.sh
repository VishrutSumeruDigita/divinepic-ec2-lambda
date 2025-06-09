#!/bin/bash

# EC2 Startup Script for TEST Environment (CPU Instance)
# This script should be added to the CPU EC2 instance User Data

set -e

# Configuration - Load from environment variables
source /home/ec2-user/.env 2>/dev/null || true
TEST_INSTANCE_ID="${TEST_INSTANCE_ID:-i-test-cpu-instance}"  # Fallback if not set
ENVIRONMENT="${ENVIRONMENT:-test}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
S3_BUCKET="${TEST_S3_BUCKET:-divinepic-test}"

# Logging
LOG_FILE="/var/log/startup-script-test.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "$(date): Starting EC2 TEST startup script..."
echo "Instance ID: $TEST_INSTANCE_ID"
echo "Environment: $ENVIRONMENT"

# Update system
echo "$(date): Updating system packages..."
yum update -y

# Install Docker if not already installed
if ! command -v docker &> /dev/null; then
    echo "$(date): Installing Docker..."
    yum install -y docker
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user
fi

# Install Docker Compose if not already installed
if ! command -v docker-compose &> /dev/null; then
    echo "$(date): Installing Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# Install AWS CLI v2 if not present
if ! command -v aws &> /dev/null; then
    echo "$(date): Installing AWS CLI v2..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    rm -rf awscliv2.zip aws
fi

# Create application directory
APP_DIR="/home/ec2-user/divinepic-test-app"
mkdir -p $APP_DIR
cd $APP_DIR

echo "$(date): Downloading TEST application files from S3..."

# Download application files for TEST environment
aws s3 cp s3://$S3_BUCKET/app-files/test/app.py . --region $AWS_REGION
aws s3 cp s3://$S3_BUCKET/app-files/test/requirements.test.txt ./requirements.txt --region $AWS_REGION
aws s3 cp s3://$S3_BUCKET/app-files/test/Dockerfile.test ./Dockerfile --region $AWS_REGION
aws s3 cp s3://$S3_BUCKET/app-files/test/constants.py . --region $AWS_REGION

# Create .env file for TEST environment
cat > .env << EOF
ENVIRONMENT=test
DEVICE=cpu
AWS_REGION=$AWS_REGION
S3_BUCKET_NAME=$S3_BUCKET
S3_UPLOAD_PATH=upload_with_embed/test
ES_HOSTS1=http://3.6.116.114:9200
INDEX_NAME=face_embeddings_test
FASTAPI_HOST=0.0.0.0
FASTAPI_PORT=8000
FACE_DETECTION_THRESHOLD=0.35
FACE_DETECTION_SIZE=640
INSTANCE_ID=$TEST_INSTANCE_ID
EOF

# Build Docker image for TEST environment
echo "$(date): Building TEST Docker image..."
docker build -t divinepic-test-fastapi .

# Stop any existing container
echo "$(date): Stopping existing TEST container if running..."
docker stop divinepic-test-container 2>/dev/null || true
docker rm divinepic-test-container 2>/dev/null || true

# Run the TEST container
echo "$(date): Starting TEST FastAPI container..."
docker run -d \
    --name divinepic-test-container \
    --restart unless-stopped \
    -p 8000:8000 \
    -v /tmp:/tmp \
    --env-file .env \
    divinepic-test-fastapi

# Wait for container to be ready
echo "$(date): Waiting for TEST FastAPI to be ready..."
sleep 45  # CPU instances need more startup time

# Health check with retry logic
echo "$(date): Performing TEST health checks..."
for i in {1..15}; do
    if curl -f http://localhost:8000/health; then
        echo "$(date): TEST FastAPI is ready!"
        break
    fi
    echo "$(date): Waiting for TEST FastAPI... (attempt $i/15)"
    sleep 10
done

# Setup auto-shutdown for TEST environment
echo "$(date): Setting up TEST auto-shutdown..."
cat > /home/ec2-user/auto-shutdown-test.sh << 'EOF'
#!/bin/bash
# Auto-shutdown script for TEST environment - stops instance after 2 hours of inactivity

IDLE_TIME=7200  # 2 hours in seconds for TEST
LOG_FILE="/var/log/auto-shutdown-test.log"
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

while true; do
    # Check if FastAPI container is processing anything
    if docker exec divinepic-test-container ps aux | grep -q "python.*app"; then
        # Check for recent activity in TEST environment
        LAST_ACTIVITY=$(docker exec divinepic-test-container find /tmp -name "*.jpg" -o -name "*.png" -newermt "2 hours ago" | wc -l)
        
        if [ $LAST_ACTIVITY -eq 0 ]; then
            echo "$(date): No TEST activity detected for 2 hours. Shutting down instance..." >> $LOG_FILE
            /usr/bin/aws ec2 stop-instances --instance-ids $INSTANCE_ID --region ap-south-1
            break
        fi
    fi
    
    sleep 600  # Check every 10 minutes for TEST
done
EOF

chmod +x /home/ec2-user/auto-shutdown-test.sh
# Enable auto-shutdown for TEST environment
nohup /home/ec2-user/auto-shutdown-test.sh &

# Create monitoring script for TEST
cat > /home/ec2-user/monitor-test.sh << 'EOF'
#!/bin/bash
echo "=== TEST Environment Monitoring ==="
echo "Container Status:"
docker ps | grep divinepic-test
echo ""
echo "CPU Usage:"
top -bn1 | grep "Cpu(s)"
echo ""
echo "Memory Usage:"
free -h
echo ""
echo "Disk Usage:"
df -h /
echo ""
echo "FastAPI Health:"
curl -s http://localhost:8000/health || echo "FastAPI not responding"
EOF

chmod +x /home/ec2-user/monitor-test.sh

echo "$(date): TEST EC2 startup script completed successfully!"
echo "$(date): TEST Environment is ready for development and testing"

# Send success notification (optional)
# aws sns publish --topic-arn "arn:aws:sns:ap-south-1:YOUR_ACCOUNT:test-instance-ready" --message "TEST GPU instance is ready" --region ap-south-1 