# syntax=docker/dockerfile:1
# ------------------------------------------------------------------
# UR10e ACT Training — OSMO Container Image
# ------------------------------------------------------------------
# Base: NVIDIA PyTorch NGC image (CUDA 12.4 + PyTorch 2.4)
# Usage:
#   docker build -t ur10e-act-train:latest -f osmo/Dockerfile ..
# ------------------------------------------------------------------

FROM nvcr.io/nvidia/pytorch:24.07-py3

LABEL maintainer="HVE Robotics"
LABEL description="UR10e ACT policy training from rosbag data"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies for OpenCV
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgl1-mesa-glx \
        libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Install azcopy for Azure Blob Storage data download
RUN curl -sL https://aka.ms/downloadazcopy-v10-linux | tar xz --strip-components=1 -C /usr/local/bin \
    && chmod +x /usr/local/bin/azcopy

WORKDIR /workspace

# Install Python dependencies (NGC image already has torch/torchvision)
# NGC base ships 'opencv 4.7.0' custom package — its cv2 module conflicts
# with pip-installed opencv-python-headless typing stubs. Remove everything
# cv2-related, then install a clean headless build.
RUN pip uninstall -y opencv-python opencv-python-headless opencv-contrib-python 2>/dev/null; \
    pip uninstall -y opencv 2>/dev/null; \
    rm -rf /usr/local/lib/python3.10/dist-packages/cv2* \
           /usr/lib/python3/dist-packages/cv2* 2>/dev/null; \
    pip install --no-cache-dir "opencv-python-headless==4.10.0.84" \
    && python -c "import cv2; print('cv2 OK:', cv2.__version__)"
COPY pyproject.toml /workspace/pyproject.toml
RUN pip install --no-cache-dir \
        "rosbags>=0.9" \
        "safetensors>=0.4" \
        "numpy<2" \
        "Pillow>=9.0" \
        "pyyaml>=6.0" \
        "tqdm>=4.60" \
        "wandb>=0.16"

# Copy training source code
COPY train.py /workspace/train.py
COPY act_model.py /workspace/act_model.py

# Copy OSMO-specific training config as default
COPY osmo/osmo-config.yaml /workspace/config.yaml

# Copy rosbag data into the image for single-node OSMO
COPY local_bags/ /data/rosbags/

# Default entrypoint: run training
ENTRYPOINT ["python", "train.py"]
CMD ["--config", "/workspace/config.yaml"]
