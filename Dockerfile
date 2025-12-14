FROM python:3.10-slim

# Use the official ComfyUI repo
ARG COMFYUI_REPO=https://github.com/Comfy-Org/ComfyUI.git
ARG COMFYUI_BRANCH=master

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    ffmpeg \
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

# Install torch + xformers first (if you want to control CUDA version)
RUN pip install --upgrade pip setuptools wheel \
 && pip install \
      "torch==2.5.1+cu121" \
      "torchvision==0.20.1+cu121" \
      "torchaudio==2.5.1+cu121" \
      --extra-index-url https://download.pytorch.org/whl/cu121 \
 && pip install "xformers==0.0.28.post3"

# Then let ComfyUI requirements pull in everything else properly
RUN pip install -r requirements.txt \
 && pip cache purge

# Extra deps for your video/manager-related custom nodes
RUN pip install \
      av \
      imageio-ffmpeg \
      toml

EXPOSE 8188

CMD ["python", "main.py", "--listen", "0.0.0.0", "--port", "8188"]
