# DivinePic Dual Environment Deployment Guide

This guide covers the complete deployment of both **TEST** (CPU) and **PRODUCTION** (GPU) environments for the DivinePic face recognition system.

## 🏗️ Architecture Overview

You now have **two separate environments**:

### TEST Environment (CPU-based)
- **Purpose**: Development and testing
- **Compute**: CPU instances (t3.large, m5.large, etc.)
- **Cost**: Lower cost for development
- **Lambda**: `divinepic-test-controller`
- **S3 Bucket**: `divinepic-test`
- **Auto-shutdown**: 2 hours of inactivity

### PRODUCTION Environment (GPU-based)
- **Purpose**: High-performance production workloads
- **Compute**: GPU instances (p3.2xlarge, g4dn.xlarge, etc.)
- **Cost**: Optimized for performance
- **Lambda**: `divinepic-prod-controller`
- **S3 Bucket**: `divinepic-prod`
- **Auto-shutdown**: 1 hour of inactivity

## 📁 File Structure

```
divinepic_g4_lambda/
├── # Lambda Functions (separate for each environment)
├── lambda-test.py              # TEST environment Lambda
├── lambda-prod.py              # PRODUCTION environment Lambda
├── lambda.py                   # Original (now deprecated)
│
├── # Docker Configurations
├── Dockerfile.test             # CPU-optimized for TEST
├── Dockerfile.prod             # GPU-optimized for PRODUCTION
├── Dockerfile.ec2              # Original GPU version
├── Dockerfile                  # Original Lambda version
│
├── # Requirements
├── requirements.test.txt       # CPU dependencies for TEST
├── requirements.prod.txt       # GPU dependencies for PRODUCTION
├── requirements.ec2.txt        # Original GPU requirements
├── requirements.txt            # Original Lambda requirements
│
├── # Startup Scripts (instance IDs managed here)
├── ec2-startup-test.sh         # TEST CPU instance setup
├── ec2-startup-prod.sh         # PRODUCTION GPU instance setup
├── ec2-startup-script.sh       # Original script
│
├── # Deployment Scripts
├── deploy-test.sh              # Deploy TEST environment
├── deploy-prod.sh              # Deploy PRODUCTION environment
├── deploy.sh                   # Original deployment script
│
├── # Application Code
├── app.py                      # FastAPI application (shared)
├── constants.py                # Configuration constants
├── docker-compose.yml          # Local development
│
└── # Documentation
├── README.md                   # Main documentation
├── TODO.md                     # Development roadmap
└── DEPLOYMENT-GUIDE.md         # This file
```

## 🚀 Quick Start

### 1. Setup Environment Variables

```bash
# Interactive setup (recommended)
chmod +x setup-env.sh
./setup-env.sh

# OR manually copy and edit
cp env.example .env
# Edit .env with your instance IDs and credentials
```

### 2. Deploy TEST Environment (CPU)

```bash
# Make deployment script executable
chmod +x deploy-test.sh

# Deploy TEST environment (reads from .env)
./deploy-test.sh
```

### 3. Deploy PRODUCTION Environment (GPU)

```bash
# Make deployment script executable
chmod +x deploy-prod.sh

# Deploy PRODUCTION environment (reads from .env)
./deploy-prod.sh
```

## 📋 Prerequisites

### For TEST Environment
- AWS CLI configured
- CPU EC2 instance (t3.large, m5.large, c5.large)
- IAM role with EC2 and S3 permissions

### For PRODUCTION Environment
- AWS CLI configured
- GPU EC2 instance (p3.2xlarge, g4dn.xlarge, etc.)
- NVIDIA drivers installed
- Docker with GPU support
- IAM role with EC2, S3, and monitoring permissions

## 🔧 Configuration

### Instance IDs are now managed via environment variables:

#### Environment Configuration File (`.env`)
```bash
# Copy env.example to .env and update these values:
TEST_INSTANCE_ID=i-your-test-cpu-instance
PROD_INSTANCE_ID=i-your-production-gpu-instance
```

#### Interactive Setup
```bash
# Use the interactive setup script
./setup-env.sh
```

### Environment Variables

#### TEST (.env)
```bash
ENVIRONMENT=test
DEVICE=cpu
S3_BUCKET_NAME=divinepic-test
INDEX_NAME=face_embeddings_test
```

#### PRODUCTION (.env)
```bash
ENVIRONMENT=production
DEVICE=cuda
CUDA_VISIBLE_DEVICES=0
S3_BUCKET_NAME=divinepic-prod
INDEX_NAME=face_embeddings_prod
```

## 🎯 Usage Examples

### TEST Environment

```bash
# Start TEST instance
aws lambda invoke \
  --function-name divinepic-test-controller \
  --payload '{"action": "start"}' \
  response.json

# Process images in TEST
aws lambda invoke \
  --function-name divinepic-test-controller \
  --payload '{"action": "start_and_process", "payload": {"files": ["test-image.jpg"]}}' \
  response.json

# Stop TEST instance
aws lambda invoke \
  --function-name divinepic-test-controller \
  --payload '{"action": "stop"}' \
  response.json
```

### PRODUCTION Environment

```bash
# Start PRODUCTION instance
aws lambda invoke \
  --function-name divinepic-prod-controller \
  --payload '{"action": "start"}' \
  response.json

# Process images in PRODUCTION
aws lambda invoke \
  --function-name divinepic-prod-controller \
  --payload '{"action": "start_and_process", "payload": {"files": ["prod-image.jpg"], "priority": "high"}}' \
  response.json

# Stop PRODUCTION instance
aws lambda invoke \
  --function-name divinepic-prod-controller \
  --payload '{"action": "stop"}' \
  response.json
```

## 📊 Monitoring

### TEST Environment
- **Logs**: `/aws/lambda/divinepic-test-controller`
- **Instance Logs**: `/var/log/startup-script-test.log`
- **Health Check**: `http://test-instance-ip:8000/health`
- **Monitoring**: `./monitor-test.sh` (on instance)

### PRODUCTION Environment
- **Logs**: `/aws/lambda/divinepic-prod-controller`
- **Instance Logs**: `/var/log/startup-script-prod.log`
- **GPU Monitoring**: `/var/log/gpu-monitor.log`
- **Health Check**: `http://prod-instance-ip:8000/health`
- **Monitoring**: `./monitor-prod.sh` (on instance)
- **CloudWatch Alarms**: Error and duration alerts

## 💰 Cost Optimization

### TEST Environment
- Uses cheaper CPU instances
- 2-hour auto-shutdown for extended development sessions
- No GPU costs
- Standard S3 storage

### PRODUCTION Environment
- 1-hour auto-shutdown for cost control
- GPU utilization monitoring
- S3 lifecycle policies (30 days → IA, 90 days → Glacier)
- CloudWatch cost alerts
- Spot instance support (configurable)

## 🔒 Security Features

### TEST Environment
- Basic IAM roles
- Standard S3 bucket
- Development-grade security

### PRODUCTION Environment
- Enhanced IAM roles with monitoring permissions
- S3 encryption at rest
- S3 versioning enabled
- Dead Letter Queue for Lambda failures
- VPC deployment (recommended)
- CloudTrail logging

## 🚨 Troubleshooting

### Common TEST Issues
1. **CPU performance**: Adjust detection threshold for CPU
2. **Instance startup**: Check CPU instance type compatibility
3. **Dependencies**: Verify CPU-only packages in requirements.test.txt

### Common PRODUCTION Issues
1. **GPU not detected**: Verify NVIDIA drivers and Docker GPU runtime
2. **CUDA errors**: Check CUDA version compatibility
3. **Memory issues**: Monitor GPU memory usage
4. **Performance**: Verify GPU utilization with `nvidia-smi`

### Debug Commands

#### TEST Environment
```bash
# SSH into TEST instance
ssh ec2-user@test-instance-ip

# Check container status
docker ps | grep divinepic-test

# Monitor resources
./monitor-test.sh

# Check logs
docker logs divinepic-test-container
```

#### PRODUCTION Environment
```bash
# SSH into PRODUCTION instance
ssh ec2-user@prod-instance-ip

# Check GPU status
nvidia-smi

# Check container GPU access
docker exec divinepic-prod-container nvidia-smi

# Monitor resources
./monitor-prod.sh

# Check logs
docker logs divinepic-prod-container
```

## 🔄 Switching Between Environments

You can run both environments simultaneously:

```bash
# Start TEST for development
aws lambda invoke --function-name divinepic-test-controller --payload '{"action": "start"}' test-response.json

# Start PRODUCTION for processing
aws lambda invoke --function-name divinepic-prod-controller --payload '{"action": "start"}' prod-response.json
```

## 📈 Scaling Considerations

### TEST Environment
- Single CPU instance sufficient
- Focus on development workflow
- Manual scaling for load testing

### PRODUCTION Environment
- Single GPU instance for start
- Future: Auto Scaling Groups
- Load balancer support
- Multi-AZ deployment

## 🎓 Best Practices

1. **Development Workflow**:
   - Use TEST for development and debugging
   - Validate on TEST before PRODUCTION deployment
   - Use PRODUCTION only for actual workloads

2. **Cost Management**:
   - Stop instances when not in use
   - Monitor AWS costs regularly
   - Use TEST for most development work

3. **Security**:
   - Regularly update dependencies
   - Monitor CloudWatch logs
   - Use least-privilege IAM roles

4. **Performance**:
   - Profile on TEST, optimize on PRODUCTION
   - Monitor GPU utilization in PRODUCTION
   - Use appropriate batch sizes

## 🤝 Support

For issues:
1. Check the environment-specific logs
2. Verify instance IDs in shell scripts
3. Test Lambda functions independently
4. Monitor CloudWatch metrics
5. Create issues in the repository

---

**Congratulations!** 🎉 You now have a complete dual-environment setup with:
- ✅ Separate TEST (CPU) and PRODUCTION (GPU) environments
- ✅ Instance IDs managed in shell scripts (not Python)
- ✅ Environment-specific Docker containers
- ✅ Dedicated Lambda functions for each environment
- ✅ Comprehensive monitoring and cost optimization
- ✅ Security and backup strategies

Choose the appropriate environment for your needs and enjoy serverless GPU computing! 🚀 