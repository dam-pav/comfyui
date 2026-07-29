FROM python:3.12-slim

# Use the official ComfyUI repo
ARG COMFYUI_REPO=https://github.com/Comfy-Org/ComfyUI.git
ARG COMFYUI_BRANCH=v0.28.0
ARG COMFYUI_MANAGER_REPO=https://github.com/Comfy-Org/ComfyUI-Manager.git
ARG COMFYUI_MANAGER_BRANCH=main
ARG A1111_PROMPT_REPO=https://github.com/Enferlain/ComfyUI-A1111-cond.git
ARG A1111_PROMPT_COMMIT=070723c767ed5bf38a5aae84fe060f34de1263dc
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

# Bundle the A1111-compatible API shim outside the custom_nodes volume so the
# compose startup can install it even when users persist that directory.
COPY custom_nodes/comfyui_a1111_api /opt/bundled_custom_nodes/comfyui_a1111_api
COPY custom_nodes/comfyui_a1111_api /opt/ComfyUI/custom_nodes/comfyui_a1111_api

# Add A1111-compatible prompt parsing and conditioning. Pin the revision so
# image rebuilds do not silently change prompt semantics.
RUN git clone ${A1111_PROMPT_REPO} /opt/bundled_custom_nodes/ComfyUI-A1111-cond \
 && git -C /opt/bundled_custom_nodes/ComfyUI-A1111-cond checkout ${A1111_PROMPT_COMMIT} \
 && rm -rf /opt/bundled_custom_nodes/ComfyUI-A1111-cond/.git \
 && cp -a /opt/bundled_custom_nodes/ComfyUI-A1111-cond custom_nodes/

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
      lark \
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
