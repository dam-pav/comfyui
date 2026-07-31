FROM python:3.12-slim

# Use the official ComfyUI repo
ARG COMFYUI_REPO=https://github.com/Comfy-Org/ComfyUI.git
ARG COMFYUI_BRANCH=v0.28.0
ARG COMFYUI_MANAGER_REPO=https://github.com/Comfy-Org/ComfyUI-Manager.git
ARG COMFYUI_MANAGER_BRANCH=main
ARG PYTORCH_VERSION=2.10.0
ARG TORCHVISION_VERSION=0.25.0
ARG TORCHAUDIO_VERSION=2.10.0
ARG XFORMERS_VERSION=0.0.34
ARG PYTORCH_INDEX_URL=https://download.pytorch.org/whl/cu126

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    ffmpeg \
    sox \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

# Clone official ComfyUI
RUN git clone --depth=1 -b ${COMFYUI_BRANCH} ${COMFYUI_REPO} ComfyUI

WORKDIR /opt/ComfyUI

# Bundle opt-in native API request logging outside the custom_nodes volume so
# compose can install it even when users persist that directory.
COPY custom_nodes/comfyui_native_api_logging /opt/bundled_custom_nodes/comfyui_native_api_logging
COPY custom_nodes/comfyui_native_api_logging /opt/ComfyUI/custom_nodes/comfyui_native_api_logging

# Bundle ComfyUI-Manager for image users who do not mount custom_nodes
RUN git clone --depth=1 -b ${COMFYUI_MANAGER_BRANCH} ${COMFYUI_MANAGER_REPO} custom_nodes/ComfyUI-Manager

# Create and use venv
RUN python -m venv /opt/ComfyUI/venv
ENV VIRTUAL_ENV=/opt/ComfyUI/venv
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"

# Upgrade pip tooling and install uv so ComfyUI-Manager can use it if it wants
RUN /opt/ComfyUI/venv/bin/python -m pip install --upgrade pip setuptools wheel uv

# Install a coherent CUDA 12.6 stack for modern NVIDIA GPUs (RTX 20 series+).
RUN /opt/ComfyUI/venv/bin/python -m pip install \
      "torch==${PYTORCH_VERSION}" \
      "torchvision==${TORCHVISION_VERSION}" \
      "torchaudio==${TORCHAUDIO_VERSION}" \
      --index-url "${PYTORCH_INDEX_URL}" \
 && /opt/ComfyUI/venv/bin/python -m pip install \
      "xformers==${XFORMERS_VERSION}" \
      --index-url "${PYTORCH_INDEX_URL}"

# Base ComfyUI requirements
RUN /opt/ComfyUI/venv/bin/python -m pip install -r requirements.txt \
 && /opt/ComfyUI/venv/bin/python -m pip cache purge

# Extra deps for your custom nodes (WanVideo, VideoHelperSuite, comfyui-manager)
RUN /opt/ComfyUI/venv/bin/python -m pip install \
      diffusers \
      gitpython \
      opencv-python-headless \
      av \
      imageio-ffmpeg \
      toml

# Install ComfyUI-Manager Python dependencies
RUN /opt/ComfyUI/venv/bin/python -m pip install --no-cache-dir \
      -r custom_nodes/ComfyUI-Manager/requirements.txt \
 && /opt/ComfyUI/venv/bin/python -m pip cache purge

# Install ComfyUI-KJNodes Python dependencies (from upstream requirements.txt)
ADD https://raw.githubusercontent.com/kijai/ComfyUI-KJNodes/main/requirements.txt \
    /tmp/kjnodes-requirements.txt

RUN /opt/ComfyUI/venv/bin/python -m pip install --no-cache-dir \
      -r /tmp/kjnodes-requirements.txt \
 && rm /tmp/kjnodes-requirements.txt \
 && /opt/ComfyUI/venv/bin/python -m pip cache purge
