ComfyUI Docker Image & Compose Template
=================================

This repository provides a ready-to-use Docker image and a `docker-compose.yml` for running ComfyUI with Nvidia GPU support. The image is built from the official upstream repository at https://github.com/Comfy-Org/ComfyUI and is updated automatically by a GitHub Actions workflow whenever new upstream changes are detected.

The parameters provide some level of flexibility; you are welcome to clone and modify the compose definition locally as required. You will still be able to pull the image.

The compose file is meant to build separate parallel containers per each GPU.

The compose definition contains a node extension init container as a bonus. If you want to run it be sure to define the COMPOSE_PROFILES environment variable. If you share the volumes between stacks, only one of them needs to run the init in order to update nodes for all your stacks.

## Deployment:
- manual: 
  - copy `docker-compose.yml` to a folder on your Linux host
  - create . .env file with the required and optional environment variables
  - run `docker compose` in the same folder.
- portainer (git): 
  - create a stack in Portainer from this Git repo using the https://github.com/dam-pav/comfyui.git address.
  - set the environment variables in the stack settings.
  - Automated pull feature will not have the effect you might expect, because building an image does not actually change the repo. In order to maintain your containers up to date use https://github.com/containrrr/watchtower or a suitable fork.

## Environment variables

- COMFYUI_PATH (required)
	- Absolute path on the host where ComfyUI data will live.
	- The compose file will use subfolders of this path for `user`, `custom_nodes`, `models`, `input`, and `output`.

- COMFYUI_GPU_DEVICE_ID (optional, default `0`)
	- Selects which GPU the container uses (as seen by Docker/NVIDIA).
	- If not set, GPU `0` is used.

- COMFYUI_PORT (optional, default `8188`)
	- Host port that will be mapped to the container’s internal port `8188`.
	- If not set, the UI is exposed on port `8188`.

- COMPOSE_PROFILES (optional)
	- Set to `kjnodes` to enable the `comfyui_init_kjnodes` init container, which installs or updates ComfyUI-KJNodes in `COMFYUI_PATH/custom_nodes`.

## Manual usage example

```bash
export COMFYUI_PATH=/srv/comfyui
export COMFYUI_GPU_DEVICE_ID=0
export COMFYUI_PORT=8188
docker compose up -d
```

In Portainer, define the same variables in the stack’s Environment tab before deploying.
