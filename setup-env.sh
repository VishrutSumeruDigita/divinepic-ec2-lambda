#!/bin/bash

# DivinePic Environment Setup Script
# This script helps you configure your environment variables

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 DivinePic Environment Setup${NC}"
echo "This script will help you configure your environment variables."
echo ""

# Check if .env already exists
if [ -f ".env" ]; then
    echo -e "${YELLOW}⚠️  .env file already exists.${NC}"
    read -p "Do you want to overwrite it? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Setup cancelled. Your existing .env file is preserved."
        exit 0
    fi
fi

# Copy example file
if [ ! -f "env.example" ]; then
    echo -e "${RED}❌ env.example file not found!${NC}"
    echo "Please ensure env.example exists in the current directory."
    exit 1
fi

cp env.example .env
echo -e "${GREEN}✅ Created .env file from env.example${NC}"

# Function to prompt for required values
prompt_for_value() {
    local var_name=$1
    local description=$2
    local current_value=$3
    local is_required=$4
    
    echo ""
    echo -e "${YELLOW}$description${NC}"
    if [ -n "$current_value" ]; then
        echo "Current value: $current_value"
    fi
    
    if [ "$is_required" = "true" ]; then
        while true; do
            read -p "Enter $var_name: " value
            if [ -n "$value" ]; then
                break
            else
                echo -e "${RED}This field is required!${NC}"
            fi
        done
    else
        read -p "Enter $var_name (optional): " value
    fi
    
    if [ -n "$value" ]; then
        # Escape special characters for sed
        escaped_value=$(echo "$value" | sed 's/[[\.*^$()+?{|]/\\&/g')
        sed -i "s|^$var_name=.*|$var_name=$escaped_value|" .env
        echo -e "${GREEN}✅ Set $var_name${NC}"
    fi
}

echo ""
echo -e "${BLUE}🏗️  Configuring AWS Settings${NC}"

# AWS Configuration
prompt_for_value "AWS_REGION" "AWS Region (e.g., ap-south-1, us-west-2)" "ap-south-1" false
prompt_for_value "AWS_ACCESS_KEY_ID" "AWS Access Key ID" "" false
prompt_for_value "AWS_SECRET_ACCESS_KEY" "AWS Secret Access Key" "" false

echo ""
echo -e "${BLUE}🖥️  Configuring Instance IDs${NC}"

# Instance Configuration
prompt_for_value "TEST_INSTANCE_ID" "TEST Environment Instance ID (CPU instance)" "" true
prompt_for_value "PROD_INSTANCE_ID" "PRODUCTION Environment Instance ID (GPU instance)" "i-08ce9b2d7eccf6d26" true

echo ""
echo -e "${BLUE}📦 Configuring S3 Buckets${NC}"

# S3 Configuration
prompt_for_value "TEST_S3_BUCKET" "TEST Environment S3 Bucket" "divinepic-test" false
prompt_for_value "PROD_S3_BUCKET" "PRODUCTION Environment S3 Bucket" "divinepic-prod" false

echo ""
echo -e "${BLUE}🔍 Configuring Elasticsearch${NC}"

# Elasticsearch Configuration
prompt_for_value "ES_HOSTS1" "Primary Elasticsearch Host" "http://3.6.116.114:9200" false

echo ""
echo -e "${BLUE}⚙️  Which environment are you setting up?${NC}"
echo "1) TEST (CPU-based development)"
echo "2) PRODUCTION (GPU-based processing)"
echo "3) Both environments"

read -p "Choose option (1-3): " env_choice

case $env_choice in
    1)
        sed -i 's|^ENVIRONMENT=.*|ENVIRONMENT=test|' .env
        sed -i 's|^DEVICE=.*|DEVICE=cpu|' .env
        echo -e "${GREEN}✅ Configured for TEST environment${NC}"
        ;;
    2)
        sed -i 's|^ENVIRONMENT=.*|ENVIRONMENT=production|' .env
        sed -i 's|^DEVICE=.*|DEVICE=cuda|' .env
        echo -e "${GREEN}✅ Configured for PRODUCTION environment${NC}"
        ;;
    3)
        echo -e "${GREEN}✅ Configured for both environments${NC}"
        echo "You can switch between environments by changing ENVIRONMENT and DEVICE variables"
        ;;
    *)
        echo -e "${YELLOW}⚠️  No environment selected. Using default (test)${NC}"
        ;;
esac

# Optional configurations
echo ""
echo -e "${YELLOW}🔧 Optional: Configure advanced settings? (y/n):${NC}"
read -p "" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    prompt_for_value "FACE_DETECTION_THRESHOLD" "Face Detection Threshold (0.1-1.0)" "0.35" false
    prompt_for_value "OMP_NUM_THREADS" "Number of CPU threads" "4" false
    prompt_for_value "TEST_AUTO_SHUTDOWN_IDLE_TIME" "TEST auto-shutdown time (seconds)" "7200" false
    prompt_for_value "PROD_AUTO_SHUTDOWN_IDLE_TIME" "PRODUCTION auto-shutdown time (seconds)" "3600" false
fi

echo ""
echo -e "${GREEN}🎉 Environment setup completed!${NC}"
echo ""
echo "Your .env file has been created with the following key settings:"
echo ""

# Show key settings
echo -e "${BLUE}Instance IDs:${NC}"
grep "^TEST_INSTANCE_ID\|^PROD_INSTANCE_ID" .env

echo ""
echo -e "${BLUE}S3 Buckets:${NC}"
grep "^TEST_S3_BUCKET\|^PROD_S3_BUCKET" .env

echo ""
echo -e "${BLUE}Current Environment:${NC}"
grep "^ENVIRONMENT\|^DEVICE" .env

echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Review and edit .env file if needed"
echo "2. Deploy TEST environment: ./deploy-test.sh"
echo "3. Deploy PRODUCTION environment: ./deploy-prod.sh"
echo "4. Test your setup with the Lambda functions"

echo ""
echo -e "${BLUE}💡 Tips:${NC}"
echo "- Keep your .env file secure and never commit it to version control"
echo "- You can run this setup script again to update your configuration"
echo "- Use TEST environment for development and PRODUCTION for actual workloads"

echo ""
echo -e "${GREEN}Happy coding! 🚀${NC}" 