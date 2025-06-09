#!/bin/bash

# EC2 Startup Script for GPU Instance with Docker FastAPI
# This script should be added to the EC2 instance User Data or run on startup

set -e

# Logging
LOG_FILE="/var/log/startup-script.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "$(date): Starting EC2 startup script..."

# Update system
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

# Create application directory
APP_DIR="/home/ec2-user/divinepic-app"
mkdir -p $APP_DIR
cd $APP_DIR

# Download application files from S3 (you'll need to upload them first)
# Replace with your actual S3 bucket and paths
AWS_REGION="ap-south-1"
S3_BUCKET="divinepic-test"  # Replace with your actual bucket

echo "$(date): Downloading application files from S3..."

# Download application files (you'll upload these to S3)
aws s3 cp s3://$S3_BUCKET/app-files/app.py . --region $AWS_REGION
aws s3 cp s3://$S3_BUCKET/app-files/requirements.txt . --region $AWS_REGION
aws s3 cp s3://$S3_BUCKET/app-files/Dockerfile . --region $AWS_REGION
aws s3 cp s3://$S3_BUCKET/app-files/.env . --region $AWS_REGION

# Build Docker image
echo "$(date): Building Docker image..."
docker build -t divinepic-fastapi .

# Stop any existing container
echo "$(date): Stopping existing container if running..."
docker stop divinepic-container 2>/dev/null || true
docker rm divinepic-container 2>/dev/null || true

# Run the container
echo "$(date): Starting FastAPI container..."
docker run -d \
    --name divinepic-container \
    --restart unless-stopped \
    -p 8000:8000 \
    -v /tmp:/tmp \
    --env-file .env \
    divinepic-fastapi

# Wait for container to be ready
echo "$(date): Waiting for FastAPI to be ready..."
sleep 30

# Health check
for i in {1..12}; do
    if curl -f http://localhost:8000/health; then
        echo "$(date): FastAPI is ready!"
        break
    fi
    echo "$(date): Waiting for FastAPI... (attempt $i/12)"
    sleep 10
done

# Setup auto-shutdown after idle time (optional)
echo "$(date): Setting up auto-shutdown..."
cat > /home/ec2-user/auto-shutdown.sh << 'EOF'
#!/bin/bash
# Auto-shutdown script - stops instance after 1 hour of inactivity

IDLE_TIME=3600  # 1 hour in seconds
LOG_FILE="/var/log/auto-shutdown.log"

while true; do
    # Check if FastAPI container is processing anything
    if docker exec divinepic-container ps aux | grep -q "python.*app"; then
        # Check for recent activity (you can customize this check)
        LAST_ACTIVITY=$(docker exec divinepic-container find /tmp -name "*.jpg" -o -name "*.png" -newermt "1 hour ago" | wc -l)
        
        if [ $LAST_ACTIVITY -eq 0 ]; then
            echo "$(date): No activity detected for 1 hour. Shutting down instance..." >> $LOG_FILE
            /usr/bin/aws ec2 stop-instances --instance-ids $(curl -s http://169.254.169.254/latest/meta-data/instance-id) --region ap-south-1
            break
        fi
    fi
    
    sleep 300  # Check every 5 minutes
done
EOF

chmod +x /home/ec2-user/auto-shutdown.sh
# Uncomment the next line if you want auto-shutdown enabled
# nohup /home/ec2-user/auto-shutdown.sh &

echo "$(date): EC2 startup script completed successfully!"

# Send success notification (optional - requires SNS topic)
# aws sns publish --topic-arn "arn:aws:sns:ap-south-1:YOUR_ACCOUNT:gpu-instance-ready" --message "GPU instance is ready" --region ap-south-1 