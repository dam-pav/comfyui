FROM python:3.10-slim

# Use the official ComfyUI repo
ARG COMFYUI_REPO=https://github.com/Comfy-Org/ComfyUI.git
ARG COMFYUI_BRANCH=master

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

# Create and use venv
RUN python -m venv /opt/ComfyUI/venv
ENV VIRTUAL_ENV=/opt/ComfyUI/venv
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"

# Upgrade pip tooling and install uv so ComfyUI-Manager can use it if it wants
RUN /opt/ComfyUI/venv/bin/python -m pip install --upgrade pip setuptools wheel uv

# Install torch + xformers first (CUDA 12.1 wheels)
RUN /opt/ComfyUI/venv/bin/python -m pip install \
      "torch==2.5.1+cu121" \
      "torchvision==0.20.1+cu121" \
      "torchaudio==2.5.1+cu121" \
      --extra-index-url https://download.pytorch.org/whl/cu121 \
 && /opt/ComfyUI/venv/bin/python -m pip install \
      "xformers==0.0.28.post3"

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

# Install ComfyUI-KJNodes Python dependencies (from upstream requirements.txt)
ADD https://raw.githubusercontent.com/kijai/ComfyUI-KJNodes/main/requirements.txt \
    /tmp/kjnodes-requirements.txt

RUN /opt/ComfyUI/venv/bin/python -m pip install --no-cache-dir \
      -r /tmp/kjnodes-requirements.txt \
 && rm /tmp/kjnodes-requirements.txt \
 && /opt/ComfyUI/venv/bin/python -m pip cache purge
