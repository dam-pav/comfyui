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

# Create a venv
RUN python -m venv /opt/ComfyUI/venv

ENV VIRTUAL_ENV=/opt/ComfyUI/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Install CUDA PyTorch & xformers
RUN pip install --upgrade pip \
 && pip install \
      "torch==2.5.1+cu121" \
      "torchvision==0.20.1+cu121" \
      "torchaudio==2.5.1+cu121" \
      --extra-index-url https://download.pytorch.org/whl/cu121 \
 && pip install "xformers==0.0.28.post3"

# Install ComfyUI core dependencies only (no deps = no conflict with torch/xformers)
RUN pip install -r requirements.txt --no-deps

# Install your extra deps for custom nodes & manager
RUN pip install \
      diffusers \
      av \
      imageio-ffmpeg \
      toml

EXPOSE 8188

CMD ["python", "main.py", "--listen", "0.0.0.0", "--port", "8188"]
