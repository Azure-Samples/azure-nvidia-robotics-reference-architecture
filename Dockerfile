# FROM nvidia/cuda:12.4.1-devel-ubuntu22.04 AS base
FROM nvidia/cuda:12.8.0-cudnn-devel-ubuntu24.04 AS base

ARG PYTHON_VERSION="3.11"
ARG TORCH_VERSION="2.10.0.dev"
ARG TORCHVISION_VERSION="0.25.0.dev"
ARG CUDA_VERSION="cu128"
ARG PYTORCH_NIGHTLY_INDEX="https://download.pytorch.org/whl/nightly/${CUDA_VERSION}"
ARG ISAACSIM_VERSION="5.0.0"
ARG ISAACLAB_REPO="https://github.com/isaac-sim/IsaacLab.git"

# Environment variables for non-interactive installation
ENV ACCEPT_EULA=Y \
    NO_NUCLEUS=Y \
    OMNI_KIT_ACCEPT_EULA=Y \
    DEBIAN_FRONTEND=noninteractive \
    PATH="/opt/isaaclab/IsaacLab/.venv/bin:$PATH" \
    VIRTUAL_ENV="/opt/isaaclab/IsaacLab/.venv" \
    UV_PROJECT_ENVIRONMENT="/opt/isaaclab/IsaacLab/.venv" \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=all \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Install system dependencies matching installer.sh
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Essential system packages
    ca-certificates curl wget git \
    # Add software-properties-common for adding PPAs
    software-properties-common \
    && add-apt-repository ppa:deadsnakes/ppa -y \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    # Graphics dependencies (extended for Isaac Sim + missing libraries)
    libgl1 libglx0 libglvnd0 libx11-6 libxext6 libsm6 \
    libxrender1 libxrandr2 libxfixes3 libxi6 libxss1 \
    libxcursor1 libxcomposite1 libxdamage1 \
    libxtst6 libxt6 libnss3 libatk-bridge2.0-0 \
    libgtk-3-0 libasound2t64 \
    # Missing GLU library
    libglu1-mesa libglu1-mesa-dev \
    # Additional graphics libraries for headless rendering
    libegl-mesa0 libegl-dev \
    mesa-utils \
    build-essential \
    # System monitoring and utilities (from installer.sh)
    nvtop \
    # SSH server (minimal)
    openssh-server sudo \
    # Utilities (minimal set)
    htop vim nano tmux rsync zip unzip \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean \
    && rm -rf /var/cache/apt/* \
    && rm -rf /tmp/* \
    && rm -rf /var/tmp/*

# Install uv package manager (faster than pip)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    mv ~/.local/bin/uv /usr/local/bin/

# Install code-server (lighter method)
RUN curl -fsSL https://code-server.dev/install.sh | sh && \
    rm -rf /tmp/code-server*

# Create uv project and environment in the final working directory
WORKDIR /opt/isaaclab
RUN git clone --depth 1 ${ISAACLAB_REPO} IsaacLab

WORKDIR /opt/isaaclab/IsaacLab
# Isaac Lab already has pyproject.toml, so just create the venv
RUN uv venv .venv --python ${PYTHON_VERSION}

# Install Python packages matching installer.sh approach
# First install PyTorch with CUDA support (nightly build required for RTX 5090 / sm_120)
RUN uv pip install --no-cache-dir --pre \
    --extra-index-url ${PYTORCH_NIGHTLY_INDEX} \
    torch torchvision torchaudio

# Downgrade NumPy to a 1.x build to maintain compatibility with Isaac Sim extensions
RUN uv pip install --no-cache-dir "numpy<2"

# Install Isaac Sim packages FIRST (before other dependencies to avoid conflicts)
RUN uv pip install --no-cache-dir \
    --extra-index-url https://pypi.nvidia.com/ \
    isaacsim[all,extscache]==${ISAACSIM_VERSION}

# Install compatible versions of dependencies AFTER Isaac Sim
RUN uv pip install --no-cache-dir \
    "skrl>=1.4.2" \
    wandb \
    azureml-core \
    azure-ai-ml \
    azure-identity \
    azure-storage-blob \
    python-dotenv \
    mlflow \
    tensorboard \
    jupyter \
    matplotlib \
    "pandas>=1.5.0,<2.0" \
    "numpy>=1.24,<2" \
    "ray[tune]==2.47.1" \
    "ray[rllib]==2.47.1" \
    opencv-python-headless

# Install Isaac Lab core packages step by step
RUN uv pip install --no-cache-dir -e ./source/isaaclab

# Install Isaac Lab tasks and assets
RUN uv pip install --no-cache-dir -e ./source/isaaclab_tasks && \
    uv pip install --no-cache-dir -e ./source/isaaclab_assets

# Install Isaac Lab RL packages
RUN uv pip install --no-cache-dir -e "./source/isaaclab_rl[skrl]" && \
    uv pip install --no-cache-dir -e "./source/isaaclab_rl[sb3]" && \
    uv pip install --no-cache-dir -e "./source/isaaclab_rl[rsl_rl]"

# Copy custom scripts for training and testing
COPY scripts ./scripts

# Clean up
RUN rm -rf .git && uv cache clean

# Configure SSH (minimal)
RUN mkdir -p /var/run/sshd /home/vscode/.ssh && \
    useradd -m -s /bin/bash vscode && \
    echo 'vscode:vscode123' | chpasswd && \
    echo 'vscode ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
    chmod 700 /home/vscode/.ssh && \
    chown vscode:vscode /home/vscode/.ssh && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    echo 'AllowUsers vscode root' >> /etc/ssh/sshd_config

# Create startup script to ensure uv environment is activated
RUN printf '#!/bin/bash\ncd /opt/isaaclab/IsaacLab\n# Activate the uv virtual environment\nsource /opt/isaaclab/IsaacLab/.venv/bin/activate\neval "$(uv generate-shell-completion bash)"\nexport UV_PROJECT_ENVIRONMENT=/opt/isaaclab/IsaacLab/.venv\nexec "$@"\n' > /usr/local/bin/entrypoint.sh && \
    chmod +x /usr/local/bin/entrypoint.sh

# Add uv activation to bashrc for interactive sessions
RUN echo 'cd /opt/isaaclab/IsaacLab' >> /home/vscode/.bashrc && \
    echo '# Activate the uv virtual environment' >> /home/vscode/.bashrc && \
    echo 'source /opt/isaaclab/IsaacLab/.venv/bin/activate' >> /home/vscode/.bashrc && \
    echo 'eval "$(uv generate-shell-completion bash)"' >> /home/vscode/.bashrc && \
    echo 'export UV_PROJECT_ENVIRONMENT=/opt/isaaclab/IsaacLab/.venv' >> /home/vscode/.bashrc && \
    chown vscode:vscode /home/vscode/.bashrc

# Set working directory
WORKDIR /opt/isaaclab/IsaacLab

# Set entrypoint to ensure uv environment activation
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Expose ports
EXPOSE 22 6060 9000

# Health check (updated to be more robust)
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}'); print(f'Device count: {torch.cuda.device_count()}'); print(f'Current device: {torch.cuda.current_device() if torch.cuda.is_available() else \"N/A\"}'); print(f'Device name: {torch.cuda.get_device_name() if torch.cuda.is_available() else \"N/A\"}')" && nc -z localhost 22
