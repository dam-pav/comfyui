# ComfyUI Docker Image & Compose

This repository provides a Docker image and `docker-compose.yml` templates for running ComfyUI with optional NVIDIA GPU support. The image is built from the official upstream repository at https://github.com/Comfy-Org/ComfyUI and is updated via a GitHub Actions workflow.

Key features:

- Builds a lightweight container based on upstream ComfyUI
- `docker-compose.yml` to run per-GPU parallel services
- Optional init container for installing/updating KJNodes

## Quick start

1. Copy `docker-compose.yml` to a folder on your Linux host.
2. Set required environment variables (see below) in a `.env` file or export them in your shell.
3. Run:

```bash
export COMFYUI_PATH=/srv/comfyui
export COMFYUI_GPU_DEVICE_ID=0
export COMFYUI_PORT=8188
docker compose up -d
```

For Portainer: create a stack from this Git repo and set the same environment variables in the stack settings.

## Environment variables

- `COMFYUI_PATH` (required): absolute host path where ComfyUI data is stored. The compose file uses subfolders `user`, `custom_nodes`, `models`, `input`, and `output` under this path.
- `COMFYUI_GPU_DEVICE_ID` (optional, default `0`): selects which GPU the container uses; used in the container name and `gpus.device_ids`.
- `COMFYUI_PORT` (optional, default `8188`): host port mapped to container port `8188`.
- `COMPOSE_PROFILES` (optional): set to `kjnodes` to enable the `comfyui_init_kjnodes` init container which installs/updates ComfyUI-KJNodes into `COMFYUI_PATH/custom_nodes`.
- `WATCHTOWER` (optional, default `false`): controls the `com.centurylinklabs.watchtower.enable` label; set to `true` to allow Watchtower detection when used.
- `CUSTOM_LABEL` (optional, default `foo=bar`): additional label value you can use for whatever reason. Remember, you can only define one single label, no more.

## Keeping containers up to date

Use tools such as `containrrr/watchtower` or `getwud/wud` to auto-update running containers when new images are published.

## Deployment:

- manual:
  - copy `docker-compose.yml` to a folder on your Linux host
  - create . .env file with the required and optional environment variables
  - run `docker compose up -d` in the same folder.
- portainer (git):
  - create a stack in Portainer from this Git repo using the https://github.com/dam-pav/comfyui.git address.
  - set the environment variables in the stack settings.
  - Automated pull feature will not have the effect you might expect, because building an image does not actually change the repo.
- In order to maintain your containers up to date based on image updates use https://github.com/containrrr/watchtower or a suitable fork. Or, you can try https://github.com/getwud/wud. This regardless whether your deployment is manual or else.

<!-- Duplicate environment section removed (see above). -->
