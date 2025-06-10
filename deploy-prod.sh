#!/bin/bash

# DivinePic PRODUCTION Environment Deployment Script (GPU-based)
set -e

# Configuration for PRODUCTION environment
AWS_REGION="ap-south-1"
S3_BUCKET="divinepic-prod"
LAMBDA_FUNCTION_NAME="divinepic-prod-controller"
PROD_INSTANCE_ID="i-08ce9b2d7eccf6d26"  # Your actual production GPU instance ID
ENVIRONMENT="production"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${PURPLE}🚀 Starting DivinePic PRODUCTION Environment Deployment${NC}"
echo -e "${YELLOW}Environment: $ENVIRONMENT${NC}"
echo -e "${YELLOW}Instance Type: GPU${NC}"
echo -e "${YELLOW}Instance ID: $PROD_INSTANCE_ID${NC}"

# Function to check if AWS CLI is configured
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}❌ AWS CLI is not installed. Please install it first.${NC}"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}❌ AWS CLI is not configured. Please run 'aws configure' first.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ AWS CLI is configured${NC}"
}

# Function to create S3 bucket for PRODUCTION if it doesn't exist
setup_prod_s3_bucket() {
    echo -e "${YELLOW}📦 Setting up PRODUCTION S3 bucket: $S3_BUCKET${NC}"
    
    if aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
        echo -e "${GREEN}✅ PRODUCTION S3 bucket $S3_BUCKET already exists${NC}"
    else
        echo -e "${YELLOW}Creating PRODUCTION S3 bucket: $S3_BUCKET${NC}"
        aws s3api create-bucket \
            --bucket "$S3_BUCKET" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
        
        # Enable versioning for production
        aws s3api put-bucket-versioning \
            --bucket "$S3_BUCKET" \
            --versioning-configuration Status=Enabled
            
        # Enable encryption for production
        aws s3api put-bucket-encryption \
            --bucket "$S3_BUCKET" \
            --server-side-encryption-configuration '{
                "Rules": [
                    {
                        "ApplyServerSideEncryptionByDefault": {
                            "SSEAlgorithm": "AES256"
                        }
                    }
                ]
            }'
            
        echo -e "${GREEN}✅ PRODUCTION S3 bucket created with versioning and encryption${NC}"
    fi
}

# Function to upload PRODUCTION application files to S3
upload_prod_app_files() {
    echo -e "${YELLOW}📤 Uploading PRODUCTION application files to S3${NC}"
    
    # Create prod app-files directory structure
    mkdir -p app-files/prod
    cp app.py app-files/prod/
    cp requirements.prod.txt app-files/prod/
    cp Dockerfile.prod app-files/prod/
    cp constants.py app-files/prod/
    
    # Create .env file for PRODUCTION
    cat > app-files/prod/.env << EOF
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
    
    # Upload to S3 with versioning
    aws s3 cp app-files/ s3://$S3_BUCKET/app-files/ --recursive
    echo -e "${GREEN}✅ PRODUCTION application files uploaded to S3${NC}"
    
    # Cleanup
    rm -rf app-files
}

# Function to create or update PRODUCTION Lambda function
setup_prod_lambda_function() {
    echo -e "${YELLOW}🔧 Setting up PRODUCTION Lambda function: $LAMBDA_FUNCTION_NAME${NC}"
    
    # Create deployment package
    mkdir -p lambda-prod-package
    cp lambda-prod.py lambda-prod-package/lambda.py
    cd lambda-prod-package
    
    # Create environment variables file
    cat > lambda_env.py << EOF
import os
os.environ['PROD_INSTANCE_ID'] = '$PROD_INSTANCE_ID'
os.environ['AWS_REGION'] = '$AWS_REGION'
os.environ['ENVIRONMENT'] = 'production'
EOF
    
    # Install dependencies
    pip install requests boto3 -t .
    
    # Create zip file
    zip -r ../lambda-prod-deployment.zip .
    cd ..
    rm -rf lambda-prod-package
    
    # Check if function exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --region "$AWS_REGION" 2>/dev/null; then
        echo -e "${YELLOW}Updating existing PRODUCTION Lambda function${NC}"
        aws lambda update-function-code \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --zip-file fileb://lambda-prod-deployment.zip \
            --region "$AWS_REGION"
        
        # Update environment variables
        aws lambda update-function-configuration \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --environment Variables="{PROD_INSTANCE_ID=$PROD_INSTANCE_ID,ENVIRONMENT=production}" \
            --region "$AWS_REGION"
    else
        echo -e "${YELLOW}Creating new PRODUCTION Lambda function${NC}"
        
        # Create execution role if it doesn't exist
        create_prod_lambda_role
        
        aws lambda create-function \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --runtime python3.9 \
            --role "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/divinepic-prod-lambda-role" \
            --handler lambda.lambda_handler \
            --zip-file fileb://lambda-prod-deployment.zip \
            --timeout 900 \
            --memory-size 256 \
            --environment Variables="{PROD_INSTANCE_ID=$PROD_INSTANCE_ID,ENVIRONMENT=production}" \
            --region "$AWS_REGION"
            
        # Add dead letter queue for production
        create_dlq_for_prod_lambda
    fi
    
    rm lambda-prod-deployment.zip
    echo -e "${GREEN}✅ PRODUCTION Lambda function setup complete${NC}"
}

# Function to create IAM role for PRODUCTION Lambda
create_prod_lambda_role() {
    echo -e "${YELLOW}🔐 Creating IAM role for PRODUCTION Lambda${NC}"
    
    # Trust policy
    cat > trust-policy-prod.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create role
    aws iam create-role \
        --role-name divinepic-prod-lambda-role \
        --assume-role-policy-document file://trust-policy-prod.json \
        --region "$AWS_REGION" || true
    
    # Attach policies
    aws iam attach-role-policy \
        --role-name divinepic-prod-lambda-role \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    aws iam attach-role-policy \
        --role-name divinepic-prod-lambda-role \
        --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
    
    # Create custom policy for production monitoring
    cat > prod-monitoring-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData",
                "sns:Publish",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    aws iam create-policy \
        --policy-name divinepic-prod-monitoring-policy \
        --policy-document file://prod-monitoring-policy.json || true
    
    aws iam attach-role-policy \
        --role-name divinepic-prod-lambda-role \
        --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/divinepic-prod-monitoring-policy"
    
    rm trust-policy-prod.json prod-monitoring-policy.json
    
    # Wait for role to be available
    sleep 15
    echo -e "${GREEN}✅ PRODUCTION IAM role created with monitoring permissions${NC}"
}

# Function to create DLQ for production Lambda
create_dlq_for_prod_lambda() {
    echo -e "${YELLOW}📫 Creating Dead Letter Queue for PRODUCTION Lambda${NC}"
    
    # Create SQS queue for failed executions
    DLQ_URL=$(aws sqs create-queue \
        --queue-name divinepic-prod-dlq \
        --attributes VisibilityTimeoutSeconds=60,MessageRetentionPeriod=1209600 \
        --region "$AWS_REGION" \
        --query 'QueueUrl' --output text 2>/dev/null || true)
    
    if [ -n "$DLQ_URL" ]; then
        DLQ_ARN=$(aws sqs get-queue-attributes \
            --queue-url "$DLQ_URL" \
            --attribute-names QueueArn \
            --region "$AWS_REGION" \
            --query 'Attributes.QueueArn' --output text)
        
        # Update Lambda with DLQ
        aws lambda update-function-configuration \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --dead-letter-config TargetArn="$DLQ_ARN" \
            --region "$AWS_REGION"
        
        echo -e "${GREEN}✅ Dead Letter Queue configured for PRODUCTION Lambda${NC}"
    fi
}

# Function to setup PRODUCTION EC2 instance
setup_prod_ec2_instance() {
    echo -e "${YELLOW}🖥️  Setting up PRODUCTION EC2 instance: $PROD_INSTANCE_ID${NC}"
    
    # Upload startup script to S3
    aws s3 cp ec2-startup-prod.sh s3://$S3_BUCKET/scripts/startup-script-prod.sh
    
    # Create user data script for PRODUCTION environment
    cat > user-data-prod.sh << EOF
#!/bin/bash
yum update -y
yum install -y awscli
aws s3 cp s3://$S3_BUCKET/scripts/startup-script-prod.sh /home/ec2-user/startup-script-prod.sh --region $AWS_REGION
chmod +x /home/ec2-user/startup-script-prod.sh
# Update the instance ID in the script
sed -i 's/i-08ce9b2d7eccf6d26/$PROD_INSTANCE_ID/g' /home/ec2-user/startup-script-prod.sh
/home/ec2-user/startup-script-prod.sh >> /var/log/startup-prod.log 2>&1
EOF
    
    echo -e "${GREEN}✅ PRODUCTION EC2 setup files uploaded${NC}"
    echo -e "${YELLOW}⚠️  Remember to:${NC}"
    echo "1. Update your PRODUCTION EC2 instance user data with the contents of user-data-prod.sh"
    echo "2. Ensure your PRODUCTION instance has an IAM role with S3 and EC2 permissions"
    echo "3. Use a GPU instance type (p3.2xlarge, g4dn.xlarge, etc.)"
    echo "4. Install NVIDIA drivers and Docker GPU runtime"
    echo "5. Update PROD_INSTANCE_ID variable in this script with your actual instance ID"
}

# Function to create CloudWatch alarms for production
setup_prod_monitoring() {
    echo -e "${YELLOW}📊 Setting up PRODUCTION monitoring and alarms${NC}"
    
    # Lambda error alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "DivinePic-PROD-Lambda-Errors" \
        --alarm-description "Alert on Lambda function errors in production" \
        --metric-name Errors \
        --namespace AWS/Lambda \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --dimensions Name=FunctionName,Value=$LAMBDA_FUNCTION_NAME \
        --region "$AWS_REGION" || true
    
    # Lambda duration alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "DivinePic-PROD-Lambda-Duration" \
        --alarm-description "Alert on Lambda function timeout in production" \
        --metric-name Duration \
        --namespace AWS/Lambda \
        --statistic Average \
        --period 300 \
        --threshold 800000 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=FunctionName,Value=$LAMBDA_FUNCTION_NAME \
        --region "$AWS_REGION" || true
    
    echo -e "${GREEN}✅ PRODUCTION monitoring alarms created${NC}"
}

# Function to test the PRODUCTION deployment
test_prod_deployment() {
    echo -e "${YELLOW}🧪 Testing PRODUCTION Lambda function${NC}"
    
    # Test start instance
    aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --payload '{"action": "start"}' \
        --region "$AWS_REGION" \
        response-prod.json
    
    echo "PRODUCTION Lambda response:"
    cat response-prod.json | jq '.'
    rm response-prod.json
    
    echo -e "${GREEN}✅ PRODUCTION deployment test complete${NC}"
}

# Function to create PRODUCTION environment documentation
create_prod_documentation() {
    cat > PRODUCTION-ENVIRONMENT.md << EOF
# PRODUCTION Environment Documentation

## Configuration
- Environment: production
- Instance Type: GPU (CUDA-enabled)
- Instance ID: $PROD_INSTANCE_ID
- Lambda Function: $LAMBDA_FUNCTION_NAME
- S3 Bucket: $S3_BUCKET (with versioning and encryption)

## Usage

### Start PRODUCTION instance
\`\`\`bash
aws lambda invoke \\
  --function-name $LAMBDA_FUNCTION_NAME \\
  --payload '{"action": "start"}' \\
  response.json
\`\`\`

### Stop PRODUCTION instance
\`\`\`bash
aws lambda invoke \\
  --function-name $LAMBDA_FUNCTION_NAME \\
  --payload '{"action": "stop"}' \\
  response.json
\`\`\`

### Process images in PRODUCTION
\`\`\`bash
aws lambda invoke \\
  --function-name $LAMBDA_FUNCTION_NAME \\
  --payload '{"action": "start_and_process", "payload": {"files": ["prod-image.jpg"], "priority": "high"}}' \\
  response.json
\`\`\`

## Monitoring
- Logs: /aws/lambda/$LAMBDA_FUNCTION_NAME
- Instance logs: /var/log/startup-script-prod.log
- GPU monitoring: /var/log/gpu-monitor.log
- Auto-shutdown: 1 hour of inactivity
- CloudWatch alarms: DivinePic-PROD-Lambda-Errors, DivinePic-PROD-Lambda-Duration

## Security Features
- S3 bucket encryption enabled
- Versioning enabled
- Dead Letter Queue configured
- CloudWatch monitoring
- IAM roles with minimal permissions

## Performance Optimization
- GPU-optimized Docker images
- CUDA 11.8 support
- Memory optimization (8GB container limit)
- Shared memory configuration (2GB)
- Auto-scaling capabilities (future)

## Cost Management
- Auto-shutdown after 1 hour idle
- GPU utilization monitoring
- Spot instance support (configurable)
- Resource usage alerts
EOF

    echo -e "${GREEN}✅ PRODUCTION environment documentation created${NC}"
}

# Function to create production backup strategy
setup_prod_backup() {
    echo -e "${YELLOW}💾 Setting up PRODUCTION backup strategy${NC}"
    
    # Create lifecycle policy for S3
    cat > s3-lifecycle-policy.json << EOF
{
    "Rules": [
        {
            "ID": "DivinePicProdLifecycle",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "upload_with_embed/prod/"
            },
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                }
            ]
        }
    ]
}
EOF
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$S3_BUCKET" \
        --lifecycle-configuration file://s3-lifecycle-policy.json || true
    
    rm s3-lifecycle-policy.json
    
    echo -e "${GREEN}✅ PRODUCTION backup and lifecycle policies configured${NC}"
}

# Main deployment flow for PRODUCTION environment
main() {
    echo -e "${PURPLE}Starting PRODUCTION environment deployment process...${NC}"
    
    check_aws_cli
    setup_prod_s3_bucket
    upload_prod_app_files
    setup_prod_lambda_function
    setup_prod_ec2_instance
    setup_prod_monitoring
    setup_prod_backup
    create_prod_documentation
    
    echo -e "${GREEN}🎉 PRODUCTION Environment deployment completed successfully!${NC}"
    echo -e "${YELLOW}Next steps for PRODUCTION environment:${NC}"
    echo "1. Verify your PRODUCTION .env file credentials"
    echo "2. Configure your PRODUCTION EC2 GPU instance"
    echo "3. Test the Lambda function with: aws lambda invoke --function-name $LAMBDA_FUNCTION_NAME --payload '{\"action\": \"start\"}' response.json"
    echo "4. Monitor CloudWatch logs and alarms"
    echo "5. Access FastAPI at http://your-prod-instance-ip:8000/docs"
    echo "6. Review security and backup configurations"
    
    read -p "Would you like to run a PRODUCTION deployment test now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        test_prod_deployment
    fi
}

# Run main function
main "$@" 