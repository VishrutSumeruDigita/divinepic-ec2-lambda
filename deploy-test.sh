#!/bin/bash

# DivinePic TEST Environment Deployment Script (CPU-based)
set -e

# Configuration for TEST environment - Load from .env if available
if [ -f ".env" ]; then
    source .env
fi

AWS_REGION="${AWS_REGION:-ap-south-1}"
S3_BUCKET="${TEST_S3_BUCKET:-divinepic-test}"
LAMBDA_FUNCTION_NAME="${TEST_LAMBDA_FUNCTION:-divinepic-test-controller}"
TEST_INSTANCE_ID="${TEST_INSTANCE_ID}"  # Must be set in .env
ENVIRONMENT="${ENVIRONMENT:-test}"

# Validate required variables
if [ -z "$TEST_INSTANCE_ID" ]; then
    echo -e "${RED}❌ TEST_INSTANCE_ID is required. Please set it in .env file${NC}"
    echo "Copy env.example to .env and update TEST_INSTANCE_ID"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧪 Starting DivinePic TEST Environment Deployment${NC}"
echo -e "${YELLOW}Environment: $ENVIRONMENT${NC}"
echo -e "${YELLOW}Instance Type: CPU${NC}"
echo -e "${YELLOW}Instance ID: $TEST_INSTANCE_ID${NC}"

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

# Function to create S3 bucket for TEST if it doesn't exist
setup_test_s3_bucket() {
    echo -e "${YELLOW}📦 Setting up TEST S3 bucket: $S3_BUCKET${NC}"
    
    if aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
        echo -e "${GREEN}✅ TEST S3 bucket $S3_BUCKET already exists${NC}"
    else
        echo -e "${YELLOW}Creating TEST S3 bucket: $S3_BUCKET${NC}"
        aws s3api create-bucket \
            --bucket "$S3_BUCKET" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
        echo -e "${GREEN}✅ TEST S3 bucket created successfully${NC}"
    fi
}

# Function to upload TEST application files to S3
upload_test_app_files() {
    echo -e "${YELLOW}📤 Uploading TEST application files to S3${NC}"
    
    # Create test app-files directory structure
    mkdir -p app-files/test
    cp app.py app-files/test/
    cp requirements.test.txt app-files/test/
    cp Dockerfile.test app-files/test/
    cp constants.py app-files/test/
    
    # Create .env file for TEST
    cat > app-files/test/.env << EOF
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
    
    # Upload to S3
    aws s3 cp app-files/ s3://$S3_BUCKET/app-files/ --recursive
    echo -e "${GREEN}✅ TEST application files uploaded to S3${NC}"
    
    # Cleanup
    rm -rf app-files
}

# Function to create or update TEST Lambda function
setup_test_lambda_function() {
    echo -e "${YELLOW}🔧 Setting up TEST Lambda function: $LAMBDA_FUNCTION_NAME${NC}"
    
    # Create deployment package
    mkdir -p lambda-test-package
    cp lambda-test.py lambda-test-package/lambda.py
    cd lambda-test-package
    
    # Create environment variables file
    cat > lambda_env.py << EOF
import os
os.environ['TEST_INSTANCE_ID'] = '$TEST_INSTANCE_ID'
os.environ['AWS_REGION'] = '$AWS_REGION'
os.environ['ENVIRONMENT'] = 'test'
EOF
    
    # Install dependencies
    pip install requests boto3 -t .
    
    # Create zip file
    zip -r ../lambda-test-deployment.zip .
    cd ..
    rm -rf lambda-test-package
    
    # Check if function exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --region "$AWS_REGION" 2>/dev/null; then
        echo -e "${YELLOW}Updating existing TEST Lambda function${NC}"
        aws lambda update-function-code \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --zip-file fileb://lambda-test-deployment.zip \
            --region "$AWS_REGION"
        
        # Update environment variables
        aws lambda update-function-configuration \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --environment Variables="{TEST_INSTANCE_ID=$TEST_INSTANCE_ID,AWS_REGION=$AWS_REGION,ENVIRONMENT=test}" \
            --region "$AWS_REGION"
    else
        echo -e "${YELLOW}Creating new TEST Lambda function${NC}"
        
        # Create execution role if it doesn't exist
        create_test_lambda_role
        
        aws lambda create-function \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --runtime python3.9 \
            --role "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/divinepic-test-lambda-role" \
            --handler lambda.lambda_handler \
            --zip-file fileb://lambda-test-deployment.zip \
            --timeout 900 \
            --memory-size 128 \
            --environment Variables="{TEST_INSTANCE_ID=$TEST_INSTANCE_ID,AWS_REGION=$AWS_REGION,ENVIRONMENT=test}" \
            --region "$AWS_REGION"
    fi
    
    rm lambda-test-deployment.zip
    echo -e "${GREEN}✅ TEST Lambda function setup complete${NC}"
}

# Function to create IAM role for TEST Lambda
create_test_lambda_role() {
    echo -e "${YELLOW}🔐 Creating IAM role for TEST Lambda${NC}"
    
    # Trust policy
    cat > trust-policy-test.json << EOF
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
        --role-name divinepic-test-lambda-role \
        --assume-role-policy-document file://trust-policy-test.json \
        --region "$AWS_REGION" || true
    
    # Attach policies
    aws iam attach-role-policy \
        --role-name divinepic-test-lambda-role \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    aws iam attach-role-policy \
        --role-name divinepic-test-lambda-role \
        --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
    
    rm trust-policy-test.json
    
    # Wait for role to be available
    sleep 10
    echo -e "${GREEN}✅ TEST IAM role created${NC}"
}

# Function to setup TEST EC2 instance
setup_test_ec2_instance() {
    echo -e "${YELLOW}🖥️  Setting up TEST EC2 instance: $TEST_INSTANCE_ID${NC}"
    
    # Upload startup script to S3
    aws s3 cp ec2-startup-test.sh s3://$S3_BUCKET/scripts/startup-script-test.sh
    
    # Create user data script for TEST environment
    cat > user-data-test.sh << EOF
#!/bin/bash
yum update -y
yum install -y awscli
aws s3 cp s3://$S3_BUCKET/scripts/startup-script-test.sh /home/ec2-user/startup-script-test.sh --region $AWS_REGION
chmod +x /home/ec2-user/startup-script-test.sh
# Update the instance ID in the script
sed -i 's/i-test-cpu-instance/$TEST_INSTANCE_ID/g' /home/ec2-user/startup-script-test.sh
/home/ec2-user/startup-script-test.sh >> /var/log/startup-test.log 2>&1
EOF
    
    echo -e "${GREEN}✅ TEST EC2 setup files uploaded${NC}"
    echo -e "${YELLOW}⚠️  Remember to:${NC}"
    echo "1. Update your TEST EC2 instance user data with the contents of user-data-test.sh"
    echo "2. Ensure your TEST instance has an IAM role with S3 and EC2 permissions"
    echo "3. Use a CPU instance type (t3.large, m5.large, etc.)"
    echo "4. Update TEST_INSTANCE_ID variable in this script with your actual instance ID"
}

# Function to test the TEST deployment
test_test_deployment() {
    echo -e "${YELLOW}🧪 Testing TEST Lambda function${NC}"
    
    # Test start instance
    aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --payload '{"action": "start"}' \
        --region "$AWS_REGION" \
        response-test.json
    
    echo "TEST Lambda response:"
    cat response-test.json | jq '.'
    rm response-test.json
    
    echo -e "${GREEN}✅ TEST deployment test complete${NC}"
}

# Function to create TEST environment documentation
create_test_documentation() {
    cat > TEST-ENVIRONMENT.md << EOF
# TEST Environment Documentation

## Configuration
- Environment: test
- Instance Type: CPU
- Instance ID: $TEST_INSTANCE_ID
- Lambda Function: $LAMBDA_FUNCTION_NAME
- S3 Bucket: $S3_BUCKET

## Usage

### Start TEST instance
\`\`\`bash
aws lambda invoke \\
  --function-name $LAMBDA_FUNCTION_NAME \\
  --payload '{"action": "start"}' \\
  response.json
\`\`\`

### Stop TEST instance
\`\`\`bash
aws lambda invoke \\
  --function-name $LAMBDA_FUNCTION_NAME \\
  --payload '{"action": "stop"}' \\
  response.json
\`\`\`

### Process images in TEST
\`\`\`bash
aws lambda invoke \\
  --function-name $LAMBDA_FUNCTION_NAME \\
  --payload '{"action": "start_and_process", "payload": {"files": ["test-image.jpg"]}}' \\
  response.json
\`\`\`

## Monitoring
- Logs: /aws/lambda/$LAMBDA_FUNCTION_NAME
- Instance logs: /var/log/startup-script-test.log
- Auto-shutdown: 2 hours of inactivity

## Cost Optimization
- Uses CPU instances (lower cost)
- Auto-shutdown after extended idle time
- Optimized for development and testing workloads
EOF

    echo -e "${GREEN}✅ TEST environment documentation created${NC}"
}

# Main deployment flow for TEST environment
main() {
    echo -e "${BLUE}Starting TEST environment deployment process...${NC}"
    
    check_aws_cli
    setup_test_s3_bucket
    upload_test_app_files
    setup_test_lambda_function
    setup_test_ec2_instance
    create_test_documentation
    
    echo -e "${GREEN}🎉 TEST Environment deployment completed successfully!${NC}"
    echo -e "${YELLOW}Next steps for TEST environment:${NC}"
    echo "1. Update your TEST .env file with the correct credentials"
    echo "2. Configure your TEST EC2 instance (CPU-based)"
    echo "3. Test the Lambda function with: aws lambda invoke --function-name $LAMBDA_FUNCTION_NAME --payload '{\"action\": \"start\"}' response.json"
    echo "4. Monitor the logs in CloudWatch"
    echo "5. Access FastAPI at http://your-test-instance-ip:8000/docs"
    
    read -p "Would you like to run a TEST deployment test now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        test_test_deployment
    fi
}

# Run main function
main "$@" 