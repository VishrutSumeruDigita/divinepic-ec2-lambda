#!/bin/bash

# DivinePic GPU Lambda Deployment Script
set -e

# Configuration
AWS_REGION="ap-south-1"
S3_BUCKET="divinepic-test"
LAMBDA_FUNCTION_NAME="divinepic-gpu-controller"
EC2_INSTANCE_ID="i-08ce9b2d7eccf6d26"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Starting DivinePic GPU Lambda Deployment${NC}"

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

# Function to create S3 bucket if it doesn't exist
setup_s3_bucket() {
    echo -e "${YELLOW}📦 Setting up S3 bucket: $S3_BUCKET${NC}"
    
    if aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
        echo -e "${GREEN}✅ S3 bucket $S3_BUCKET already exists${NC}"
    else
        echo -e "${YELLOW}Creating S3 bucket: $S3_BUCKET${NC}"
        aws s3api create-bucket \
            --bucket "$S3_BUCKET" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
        echo -e "${GREEN}✅ S3 bucket created successfully${NC}"
    fi
}

# Function to upload application files to S3
upload_app_files() {
    echo -e "${YELLOW}📤 Uploading application files to S3${NC}"
    
    # Create app-files directory structure
    mkdir -p app-files
    cp app.py app-files/
    cp requirements.ec2.txt app-files/requirements.txt
    cp Dockerfile.ec2 app-files/Dockerfile
    cp constants.py app-files/
    
    # Create .env file from example
    if [ ! -f ".env" ]; then
        echo -e "${YELLOW}⚠️  Creating .env file from template. Please update it with your credentials.${NC}"
        cat > .env << EOF
AWS_REGION=$AWS_REGION
S3_BUCKET_NAME=$S3_BUCKET
S3_UPLOAD_PATH=upload_with_embed
ES_HOSTS1=http://3.6.116.114:9200
INDEX_NAME=face_embeddings
FASTAPI_HOST=0.0.0.0
FASTAPI_PORT=8000
FACE_DETECTION_THRESHOLD=0.35
FACE_DETECTION_SIZE=640
CUDA_VISIBLE_DEVICES=0
OMP_NUM_THREADS=4
MKL_NUM_THREADS=4
EOF
    fi
    
    cp .env app-files/
    
    # Upload to S3
    aws s3 cp app-files/ s3://$S3_BUCKET/app-files/ --recursive
    echo -e "${GREEN}✅ Application files uploaded to S3${NC}"
    
    # Cleanup
    rm -rf app-files
}

# Function to create or update Lambda function
setup_lambda_function() {
    echo -e "${YELLOW}🔧 Setting up Lambda function: $LAMBDA_FUNCTION_NAME${NC}"
    
    # Create deployment package
    mkdir -p lambda-package
    cp lambda.py lambda-package/
    cd lambda-package
    
    # Install dependencies
    pip install requests boto3 -t .
    
    # Create zip file
    zip -r ../lambda-deployment.zip .
    cd ..
    rm -rf lambda-package
    
    # Check if function exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --region "$AWS_REGION" 2>/dev/null; then
        echo -e "${YELLOW}Updating existing Lambda function${NC}"
        aws lambda update-function-code \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --zip-file fileb://lambda-deployment.zip \
            --region "$AWS_REGION"
    else
        echo -e "${YELLOW}Creating new Lambda function${NC}"
        
        # Create execution role if it doesn't exist
        create_lambda_role
        
        aws lambda create-function \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --runtime python3.9 \
            --role "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/divinepic-lambda-role" \
            --handler lambda.lambda_handler \
            --zip-file fileb://lambda-deployment.zip \
            --timeout 900 \
            --memory-size 128 \
            --region "$AWS_REGION"
    fi
    
    rm lambda-deployment.zip
    echo -e "${GREEN}✅ Lambda function setup complete${NC}"
}

# Function to create IAM role for Lambda
create_lambda_role() {
    echo -e "${YELLOW}🔐 Creating IAM role for Lambda${NC}"
    
    # Trust policy
    cat > trust-policy.json << EOF
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
        --role-name divinepic-lambda-role \
        --assume-role-policy-document file://trust-policy.json \
        --region "$AWS_REGION" || true
    
    # Attach policies
    aws iam attach-role-policy \
        --role-name divinepic-lambda-role \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    aws iam attach-role-policy \
        --role-name divinepic-lambda-role \
        --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
    
    rm trust-policy.json
    
    # Wait for role to be available
    sleep 10
    echo -e "${GREEN}✅ IAM role created${NC}"
}

# Function to setup EC2 instance
setup_ec2_instance() {
    echo -e "${YELLOW}🖥️  Setting up EC2 instance: $EC2_INSTANCE_ID${NC}"
    
    # Upload startup script to S3
    aws s3 cp ec2-startup-script.sh s3://$S3_BUCKET/scripts/startup-script.sh
    
    # Create user data script that downloads and runs the startup script
    cat > user-data.sh << 'EOF'
#!/bin/bash
yum update -y
yum install -y awscli
aws s3 cp s3://divinepic-test/scripts/startup-script.sh /home/ec2-user/startup-script.sh --region ap-south-1
chmod +x /home/ec2-user/startup-script.sh
/home/ec2-user/startup-script.sh >> /var/log/startup.log 2>&1
EOF
    
    echo -e "${GREEN}✅ EC2 setup files uploaded. You can now update your instance user data with the script in user-data.sh${NC}"
    echo -e "${YELLOW}⚠️  Remember to:${NC}"
    echo "1. Update your EC2 instance user data with the contents of user-data.sh"
    echo "2. Ensure your instance has an IAM role with S3 and EC2 permissions"
    echo "3. Install NVIDIA drivers and Docker on your GPU instance"
}

# Function to test the deployment
test_deployment() {
    echo -e "${YELLOW}🧪 Testing Lambda function${NC}"
    
    # Test start instance
    aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --payload '{"action": "start"}' \
        --region "$AWS_REGION" \
        response.json
    
    echo "Lambda response:"
    cat response.json
    rm response.json
    
    echo -e "${GREEN}✅ Test complete${NC}"
}

# Main deployment flow
main() {
    echo -e "${GREEN}Starting deployment process...${NC}"
    
    check_aws_cli
    setup_s3_bucket
    upload_app_files
    setup_lambda_function
    setup_ec2_instance
    
    echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Update your .env file with the correct credentials"
    echo "2. Configure your EC2 instance with GPU drivers and Docker"
    echo "3. Test the Lambda function with: aws lambda invoke --function-name $LAMBDA_FUNCTION_NAME --payload '{\"action\": \"start\"}' response.json"
    echo "4. Monitor the logs in CloudWatch"
    
    read -p "Would you like to run a test now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        test_deployment
    fi
}

# Run main function
main "$@" 