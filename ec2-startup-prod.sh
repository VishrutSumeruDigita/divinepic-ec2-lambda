#!/bin/bash

# EC2 Startup Script for PRODUCTION Environment (GPU Instance)
# This script should be added to the GPU EC2 instance User Data

set -e

# Configuration - Load from environment variables
source /home/ec2-user/.env 2>/dev/null || true
PROD_INSTANCE_ID="${PROD_INSTANCE_ID:-i-08ce9b2d7eccf6d26}"  # Fallback if not set
ENVIRONMENT="${ENVIRONMENT:-production}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
S3_BUCKET="${PROD_S3_BUCKET:-divinepic-prod}"

# Logging
LOG_FILE="/var/log/startup-script-prod.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "$(date): Starting EC2 PRODUCTION startup script..."
echo "Instance ID: $PROD_INSTANCE_ID"
echo "Environment: $ENVIRONMENT"

# Update system
echo "$(date): Updating system packages..."
yum update -y

# Install NVIDIA drivers if not already installed (for GPU instances)
if ! command -v nvidia-smi &> /dev/null; then
    echo "$(date): Installing NVIDIA drivers..."
    yum install -y gcc kernel-devel-$(uname -r)
    
    # Download and install NVIDIA driver
    wget -q https://us.download.nvidia.com/tesla/470.199.02/NVIDIA-Linux-x86_64-470.199.02.run
    chmod +x NVIDIA-Linux-x86_64-470.199.02.run
    ./NVIDIA-Linux-x86_64-470.199.02.run --silent
    rm NVIDIA-Linux-x86_64-470.199.02.run
    
    echo "$(date): NVIDIA drivers installed"
fi

# Install Docker if not already installed
if ! command -v docker &> /dev/null; then
    echo "$(date): Installing Docker..."
    yum install -y docker
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user
fi

# Install NVIDIA Docker runtime for GPU support
if ! docker info | grep -q nvidia; then
    echo "$(date): Installing NVIDIA Docker runtime..."
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.repo | \
        tee /etc/yum.repos.d/nvidia-docker.repo
    yum install -y nvidia-docker2
    systemctl restart docker
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

# Verify GPU is available
echo "$(date): Verifying GPU availability..."
nvidia-smi
if [ $? -ne 0 ]; then
    echo "$(date): ERROR: GPU not available!"
    exit 1
fi

# Create application directory
APP_DIR="/home/ec2-user/divinepic-prod-app"
mkdir -p $APP_DIR
cd $APP_DIR

echo "$(date): Downloading PRODUCTION application files from S3..."

# Download application files for PRODUCTION environment
aws s3 cp s3://$S3_BUCKET/app-files/prod/app.py . --region $AWS_REGION
aws s3 cp s3://$S3_BUCKET/app-files/prod/requirements.prod.txt ./requirements.txt --region $AWS_REGION
aws s3 cp s3://$S3_BUCKET/app-files/prod/Dockerfile.prod ./Dockerfile --region $AWS_REGION
aws s3 cp s3://$S3_BUCKET/app-files/prod/constants.py . --region $AWS_REGION

# Create .env file for PRODUCTION environment
cat > .env << EOF
ENVIRONMENT=production
DEVICE=cuda
CUDA_VISIBLE_DEVICES=0
AWS_REGION=$AWS_REGION
S3_BUCKET_NAME=$S3_BUCKET
S3_UPLOAD_PATH=upload_with_embed/prod
ES_HOSTS1=http://3.6.116.114:9200
INDEX_NAME=face_embeddings_prod
FASTAPI_HOST=0.0.0.0
FASTAPI_PORT=8000
FACE_DETECTION_THRESHOLD=0.35
FACE_DETECTION_SIZE=640
PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:128
INSTANCE_ID=$PROD_INSTANCE_ID
EOF

# Build Docker image for PRODUCTION environment
echo "$(date): Building PRODUCTION Docker image..."
docker build -t divinepic-prod-fastapi .

# Stop any existing container
echo "$(date): Stopping existing PRODUCTION container if running..."
docker stop divinepic-prod-container 2>/dev/null || true
docker rm divinepic-prod-container 2>/dev/null || true

# Run the PRODUCTION container with GPU support
echo "$(date): Starting PRODUCTION FastAPI container with GPU support..."
docker run -d \
    --name divinepic-prod-container \
    --restart unless-stopped \
    --gpus all \
    -p 8000:8000 \
    -v /tmp:/tmp \
    --env-file .env \
    --shm-size=2g \
    --memory=8g \
    divinepic-prod-fastapi

# Wait for container to be ready (GPU needs more time)
echo "$(date): Waiting for PRODUCTION FastAPI to be ready..."
sleep 90  # GPU instances need more startup time for driver initialization

# Health check with retry logic
echo "$(date): Performing PRODUCTION health checks..."
for i in {1..20}; do
    if curl -f http://localhost:8000/health; then
        echo "$(date): PRODUCTION FastAPI is ready!"
        # Additional GPU health check
        if docker exec divinepic-prod-container nvidia-smi; then
            echo "$(date): GPU is accessible within container!"
        else
            echo "$(date): WARNING: GPU not accessible within container"
        fi
        break
    fi
    echo "$(date): Waiting for PRODUCTION FastAPI... (attempt $i/20)"
    sleep 15
done

# Setup auto-shutdown for PRODUCTION environment (shorter idle time)
echo "$(date): Setting up PRODUCTION auto-shutdown..."
cat > /home/ec2-user/auto-shutdown-prod.sh << 'EOF'
#!/bin/bash
# Auto-shutdown script for PRODUCTION environment - stops instance after 1 hour of inactivity

IDLE_TIME=3600  # 1 hour in seconds for PRODUCTION
LOG_FILE="/var/log/auto-shutdown-prod.log"
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

while true; do
    # Check if FastAPI container is processing anything
    if docker exec divinepic-prod-container ps aux | grep -q "python.*app"; then
        # Check for recent activity in PRODUCTION environment
        LAST_ACTIVITY=$(docker exec divinepic-prod-container find /tmp -name "*.jpg" -o -name "*.png" -newermt "1 hour ago" | wc -l)
        
        # Also check GPU utilization
        GPU_UTIL=$(docker exec divinepic-prod-container nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -1)
        
        if [ $LAST_ACTIVITY -eq 0 ] && [ "${GPU_UTIL:-0}" -lt 5 ]; then
            echo "$(date): No PRODUCTION activity detected for 1 hour and GPU idle. Shutting down instance..." >> $LOG_FILE
            /usr/bin/aws ec2 stop-instances --instance-ids $INSTANCE_ID --region ap-south-1
            break
        fi
    fi
    
    sleep 300  # Check every 5 minutes for PRODUCTION
done
EOF

chmod +x /home/ec2-user/auto-shutdown-prod.sh
# Enable auto-shutdown for PRODUCTION environment
nohup /home/ec2-user/auto-shutdown-prod.sh &

# Create monitoring script for PRODUCTION
cat > /home/ec2-user/monitor-prod.sh << 'EOF'
#!/bin/bash
echo "=== PRODUCTION Environment Monitoring ==="
echo "Container Status:"
docker ps | grep divinepic-prod
echo ""
echo "GPU Status:"
nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv
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
echo ""
echo "Container GPU Access:"
docker exec divinepic-prod-container nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader || echo "GPU not accessible in container"
EOF

chmod +x /home/ec2-user/monitor-prod.sh

# Setup GPU monitoring and alerting
cat > /home/ec2-user/gpu-monitor.sh << 'EOF'
#!/bin/bash
# GPU monitoring script for PRODUCTION environment

LOG_FILE="/var/log/gpu-monitor.log"

while true; do
    # Get GPU metrics
    GPU_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits)
    GPU_UTIL=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits)
    GPU_MEM=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
    
    # Log metrics
    echo "$(date): GPU Temp: ${GPU_TEMP}°C, Util: ${GPU_UTIL}%, Mem: ${GPU_MEM}MB" >> $LOG_FILE
    
    # Alert if temperature too high
    if [ "${GPU_TEMP:-0}" -gt 85 ]; then
        echo "$(date): WARNING: GPU temperature high: ${GPU_TEMP}°C" >> $LOG_FILE
        # Could send SNS notification here
    fi
    
    sleep 60
done
EOF

chmod +x /home/ec2-user/gpu-monitor.sh
nohup /home/ec2-user/gpu-monitor.sh &

echo "$(date): PRODUCTION EC2 startup script completed successfully!"
echo "$(date): PRODUCTION Environment is ready for high-performance processing"
echo "$(date): GPU Status:"
nvidia-smi

# Send success notification (optional)
# aws sns publish --topic-arn "arn:aws:sns:ap-south-1:YOUR_ACCOUNT:prod-instance-ready" --message "PRODUCTION GPU instance is ready" --region ap-south-1 