FROM public.ecr.aws/lambda/python:3.10-x86_64

# Install system dependencies
RUN yum update -y && \
    yum install -y wget unzip gcc gcc-c++ cmake make && \
    yum clean all

# Set environment variables for Lambda
ENV MPLCONFIGDIR=/app/.matplotlib
ENV NUMBA_CACHE_DIR=/tmp
ENV OMP_NUM_THREADS=1
ENV MKL_NUM_THREADS=1
ENV OPENBLAS_NUM_THREADS=1
ENV INSIGHTFACE_ROOT=/app/.insightface

# Download and setup AntelopeV2 model files
RUN cd /tmp && \
    wget -q https://github.com/deepinsight/insightface/releases/download/v0.7/antelopev2.zip && \
    if [ ! -f "antelopev2.zip" ]; then echo "Failed to download model"; exit 1; fi && \
    unzip -q antelopev2.zip -d antelopev2_files && \
    if [ ! -d "antelopev2_files" ]; then echo "Failed to extract model"; exit 1; fi && \
    mkdir -p /app/models/antelopev2/detection && \
    cp antelopev2_files/antelopev2/scrfd_10g_bnkps.onnx /app/models/antelopev2/detection/ && \
    cp antelopev2_files/antelopev2/glintr100.onnx /app/models/antelopev2/ && \
    if [ ! -f "/app/models/antelopev2/detection/scrfd_10g_bnkps.onnx" ] || [ ! -f "/app/models/antelopev2/glintr100.onnx" ]; then \
        echo "Failed to copy model files"; exit 1; \
    fi && \
    rm -rf /tmp/antelopev2*

# Create necessary directories
RUN mkdir -p /tmp/uploads && \
    mkdir -p /app/.insightface && \
    mkdir -p /app/.matplotlib

# Copy function code
ADD serving_api.tar.gz ${LAMBDA_TASK_ROOT}

# Install Python packages using requirements.txt
RUN pip3 install --upgrade pip && \
    pip3 install --no-cache-dir --target ${LAMBDA_TASK_ROOT} -r requirements.txt

CMD [ "serving_api.lambda_handler" ]