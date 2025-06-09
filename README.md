# DivinePic GPU Lambda Architecture

A serverless GPU computing solution that uses AWS Lambda to trigger EC2 GPU instances running FastAPI for image processing and face recognition.

## Architecture Overview

```
┌─────────────────────┐
│  Lambda Function    │
│ (Trigger on Invoke) │
└──────────┬──────────┘
           │
           ▼
┌───────────────────────────────┐
│     EC2 GPU Instance          │
│  (Starts when triggered)      │
│                               │
│  ┌─────────────────────────┐  │
│  │  Docker Container       │  │
│  │  (FastAPI App)          │  │
│  └─────────┬───────┬───────┘  │
│           │       │           │
│           │       ▼           │
│           │   ┌────────────┐  │
│           │   │ S3 Bucket  │  │
│           │   │ (Images)   │  │
│           │   └────────────┘  │
│           │                   │
│           ▼                   │
│  ┌────────────────────────┐   │
│  │ Elasticsearch (Remote) │   │
│  │ (Vector Storage)       │   │
│  └────────────────────────┘   │
└───────────────────────────────┘
```

## Features

- **Serverless GPU Computing**: On-demand GPU instance activation via Lambda
- **Face Recognition**: Advanced face detection and embedding generation using InsightFace
- **Scalable Storage**: Images stored in S3, vectors in Elasticsearch
- **Cost Efficient**: Instances only run when needed
- **Auto-shutdown**: Automatic instance termination after idle period
- **Health Monitoring**: Built-in health checks and monitoring

## Components

### 1. Lambda Function (`lambda.py`)
- Starts/stops EC2 GPU instances
- Monitors instance health
- Triggers FastAPI processing
- Handles error recovery

### 2. FastAPI Application (`app.py`)
- Face detection and recognition
- Image upload handling
- S3 integration
- Elasticsearch indexing
- Background task processing

### 3. EC2 GPU Instance
- NVIDIA GPU support
- Docker containerization
- Auto-startup scripts
- Performance optimization

### 4. Docker Configuration
- **`Dockerfile`**: Lambda runtime (CPU)
- **`Dockerfile.ec2`**: EC2 GPU runtime (CUDA)
- **`docker-compose.yml`**: Local development

## Quick Start

### Prerequisites
- AWS CLI configured
- Python 3.9+
- Docker (for local development)
- EC2 GPU instance (p2, p3, g4dn, etc.)

### 1. Clone and Setup
```bash
git clone <repository>
cd divinepic_g4_lambda
chmod +x deploy.sh
```

### 2. Configure Environment
```bash
# Copy and edit environment variables
cp .env.example .env
# Edit .env with your AWS credentials and configuration
```

### 3. Deploy Infrastructure
```bash
./deploy.sh
```

### 4. Manual EC2 Setup (One-time)
1. Launch a GPU instance (p3.2xlarge, g4dn.xlarge, etc.)
2. Install NVIDIA drivers and Docker
3. Configure the startup script from `user-data.sh`

## Usage

### Trigger via Lambda
```bash
# Start instance and process images
aws lambda invoke \
  --function-name divinepic-gpu-controller \
  --payload '{"action": "start_and_process", "payload": {"files": ["image1.jpg"]}}' \
  response.json

# Just start instance
aws lambda invoke \
  --function-name divinepic-gpu-controller \
  --payload '{"action": "start"}' \
  response.json

# Stop instance
aws lambda invoke \
  --function-name divinepic-gpu-controller \
  --payload '{"action": "stop"}' \
  response.json
```

### Direct API Usage
```bash
# Health check
curl http://your-instance-ip:8000/health

# Upload images
curl -X POST "http://your-instance-ip:8000/upload-images/" \
  -H "Content-Type: multipart/form-data" \
  -F "files=@image1.jpg" \
  -F "files=@image2.jpg"
```

## Configuration

### Environment Variables
```bash
# AWS Configuration
AWS_REGION=ap-south-1
S3_BUCKET_NAME=your-bucket-name
S3_UPLOAD_PATH=upload_with_embed

# Elasticsearch
ES_HOSTS1=http://your-es-host:9200
INDEX_NAME=face_embeddings

# Performance
CUDA_VISIBLE_DEVICES=0
OMP_NUM_THREADS=4
```

### Instance Types
Recommended EC2 instance types:
- **Development**: g4dn.xlarge (1 GPU, $0.526/hour)
- **Production**: p3.2xlarge (1 V100, $3.06/hour)
- **High Performance**: p3.8xlarge (4 V100s, $12.24/hour)

## File Structure

```
divinepic_g4_lambda/
├── lambda.py                 # Lambda function code
├── app.py                    # FastAPI application
├── constants.py              # Configuration constants
├── requirements.txt          # Lambda dependencies
├── requirements.ec2.txt      # EC2 dependencies
├── Dockerfile               # Lambda container
├── Dockerfile.ec2           # EC2 GPU container
├── docker-compose.yml       # Local development
├── ec2-startup-script.sh    # EC2 initialization
├── deploy.sh               # Deployment automation
├── TODO.md                 # Development roadmap
└── README.md              # This file
```

## Monitoring and Logs

### CloudWatch Logs
- Lambda logs: `/aws/lambda/divinepic-gpu-controller`
- EC2 startup: `/var/log/startup-script.log`

### Instance Monitoring
```bash
# SSH into EC2 instance
docker logs divinepic-container
docker exec divinepic-container nvidia-smi
```

### Health Checks
```bash
# Check FastAPI health
curl http://your-instance-ip:8000/health

# Check Elasticsearch connection
curl http://your-instance-ip:8000/test-es
```

## Cost Optimization

### Auto-shutdown
The system includes automatic shutdown after idle periods:
- Default: 1 hour of inactivity
- Configurable via `AUTO_SHUTDOWN_IDLE_TIME`
- Monitors file activity and API usage

### Spot Instances
Consider using Spot Instances for cost savings:
```bash
# Request spot instance (up to 70% savings)
aws ec2 request-spot-instances \
  --spot-price "0.50" \
  --instance-count 1 \
  --type "one-time" \
  --launch-specification file://spot-config.json
```

## Troubleshooting

### Common Issues

1. **Instance fails to start**
   - Check IAM permissions
   - Verify instance ID in configuration
   - Check AWS service limits

2. **Docker container not starting**
   - Check NVIDIA drivers installation
   - Verify Docker GPU support: `docker run --gpus all nvidia/cuda:11.8-base nvidia-smi`

3. **FastAPI not accessible**
   - Check security group (port 8000)
   - Verify public IP assignment
   - Check application logs

4. **S3/Elasticsearch errors**
   - Verify credentials and permissions
   - Check network connectivity
   - Test endpoints manually

### Debug Commands
```bash
# Check GPU availability
nvidia-smi

# Test Docker GPU
docker run --gpus all nvidia/cuda:11.8-base nvidia-smi

# Check application logs
docker logs divinepic-container

# Monitor resource usage
htop
nvidia-smi -l 1
```

## Development

### Local Development
```bash
# Start services locally
docker-compose up -d

# Run FastAPI directly
uvicorn app:app --reload --host 0.0.0.0 --port 8000
```

### Testing
```bash
# Test Lambda function locally
python -c "
import lambda_function
import json
event = {'action': 'start'}
context = {}
result = lambda_function.lambda_handler(event, context)
print(json.dumps(result, indent=2))
"
```

## Security Considerations

1. **IAM Roles**: Use least-privilege IAM roles
2. **Security Groups**: Restrict access to necessary ports
3. **VPC**: Consider deploying in private subnets
4. **Encryption**: Enable S3 and EBS encryption
5. **Secrets**: Use AWS Secrets Manager for sensitive data

## Performance Tuning

### GPU Optimization
- Use CUDA-optimized Docker images
- Set appropriate `CUDA_VISIBLE_DEVICES`
- Monitor GPU memory usage

### Application Optimization
- Batch image processing
- Use connection pooling for Elasticsearch
- Implement proper caching strategies

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

MIT License - see LICENSE file for details

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review CloudWatch logs
3. Create an issue in the repository
