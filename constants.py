# Application Constants
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# AWS Configuration
AWS_REGION = os.getenv("AWS_REGION", "ap-south-1")
S3_BUCKET_NAME = os.getenv("S3_BUCKET_NAME", "divinepic-test")
S3_UPLOAD_PATH = os.getenv("S3_UPLOAD_PATH", "upload_with_embed")

# Elasticsearch Configuration
ES_HOSTS = [
    os.getenv("ES_HOSTS1", "http://3.6.116.114:9200"),
    # os.getenv("ES_HOSTS2", ""),  # Add second host if needed
]
INDEX_NAME = os.getenv("INDEX_NAME", "face_embeddings")

# FastAPI Configuration
FASTAPI_HOST = os.getenv("FASTAPI_HOST", "0.0.0.0")
FASTAPI_PORT = int(os.getenv("FASTAPI_PORT", "8000"))

# Model Configuration
FACE_DETECTION_THRESHOLD = float(os.getenv("FACE_DETECTION_THRESHOLD", "0.35"))
FACE_DETECTION_SIZE = int(os.getenv("FACE_DETECTION_SIZE", "640"))

# File Upload Configuration
MAX_FILE_SIZE = 50 * 1024 * 1024  # 50MB
ALLOWED_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".tiff", ".webp"}
TEMP_UPLOAD_DIR = "/tmp/uploads"

# EC2 Configuration
TEST_INSTANCE_ID = os.getenv("TEST_INSTANCE_ID")
PROD_INSTANCE_ID = os.getenv("PROD_INSTANCE_ID")
EC2_INSTANCE_ID = os.getenv("EC2_INSTANCE_ID", PROD_INSTANCE_ID or "i-08ce9b2d7eccf6d26")  # Backward compatibility
MAX_INSTANCE_WAIT_TIME = 300  # 5 minutes

# Logging Configuration
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")

# Performance Configuration
MAX_CONCURRENT_UPLOADS = int(os.getenv("MAX_CONCURRENT_UPLOADS", "5"))
BACKGROUND_TASK_TIMEOUT = int(os.getenv("BACKGROUND_TASK_TIMEOUT", "1800"))  # 30 minutes

# Auto-shutdown Configuration
AUTO_SHUTDOWN_IDLE_TIME = int(os.getenv("AUTO_SHUTDOWN_IDLE_TIME", "3600"))  # 1 hour
