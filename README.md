# ComfyUI Docker Image & Compose

This repository provides a ready-to-use Docker image and a `docker-compose.yml` for running ComfyUI with Nvidia GPU support. The image is built from the official upstream repository at https://github.com/Comfy-Org/ComfyUI and is updated automatically by a GitHub Actions workflow whenever new upstream changes are detected.

`ComfyUI-Manager` is included as part of the package. The image bundles it for direct `docker run` usage, and the compose startup command will clone it into the persistent `custom_nodes` volume automatically if it is missing.

The image also includes a lightweight AUTOMATIC1111-compatible API shim for
clients that expect `/sdapi/v1` endpoints. It runs on the same host and port as
ComfyUI; no second service or port is required.

The image targets modern NVIDIA GPUs (RTX 20 series and newer) with Python 3.12,
PyTorch 2.10, and CUDA 12.6 wheels. ComfyUI async weight offloading uses its
upstream default. The default ComfyUI source revision is pinned to the stable
`v0.28.0` release and can be changed with the `COMFYUI_BRANCH` build argument.

The parameters provide some level of flexibility; you are welcome to clone and modify the compose definition locally as required. You will still be able to pull the image.

The compose file is meant to build separate parallel containers per each GPU.

The compose definition contains a node extension init container as a bonus. If you want to run it be sure to define the COMPOSE_PROFILES environment variable. Enable the init container for one stack only. Since the volumes are shared, the one will update nodes for all your stacks.

## Host prerequisites

For Ubuntu and Debian hosts with an NVIDIA GPU, the included prerequisite utility installs the NVIDIA driver, Docker Engine with the Compose plugin, and the NVIDIA Container Toolkit:

```bash
sudo ./Utils/install_ComfyUI_Prerequisites.sh
```

The script configures Docker to use the NVIDIA runtime and validates GPU access from a container. A reboot may be required after installing the GPU driver for the first time.

## Deployment:
- manual: 
  - copy `docker-compose.yml` to a folder on your Linux host
  - create . .env file with the required and optional environment variables
  - run `docker compose` in the same folder.
- portainer (git): 
  - create a stack in Portainer from this Git repo using the https://github.com/dam-pav/comfyui.git address.
  - set the environment variables in the stack settings.
  - You can take advantage of the automated updates feature.

## Environment variables

- `COMFYUI_PATH` (required)
	- Absolute path on the host where ComfyUI data will live.
	- The compose file will use shared subfolders of this path for `user`,
	  `custom_nodes`, `models`, `input`, and `output`.
	- Each GPU instance uses a separate SQLite file in the shared user folder:
	  `comfyui-gpu<device-id>.db`. This avoids ComfyUI's exclusive database
	  lock while keeping user settings and configuration shared.

- `COMFYUI_GPU_DEVICE_ID` (optional, default `0`)
	- Selects which GPU the container uses (as seen by Docker/NVIDIA).
	- If not set, GPU `0` is used.

- `COMFYUI_PORT` (optional, default `8188`)
	- Host port that will be mapped to the container’s internal port `8188`.
	- If not set, the UI is exposed on port `8188`.

- `COMPOSE_PROFILES` (optional)
  - Set to `kjnodes` to enable the `comfyui_init_kjnodes` init container, which installs or updates ComfyUI-KJNodes in `COMFYUI_PATH/custom_nodes`.
- `COMFYUI_MANAGER_SECURITY_LEVEL` (optional)
	- Overrides the `ComfyUI-Manager` `security_level` written to the persistent user config.
	- If not set and no manager config exists yet, the compose startup creates one with `security_level = normal`, which matches the current recommended Manager default and allows registered node installs, updates, and restarts.
	- If you already have a manager config, it is preserved unless this variable is explicitly set.
	- The compose startup writes `user/__manager/config.ini`, which is the current protected Manager config path.
- `A1111_API_SAMPLER` (optional)
	- Forces a sampler for A1111 API requests when the client does not expose a
	  useful sampler control. Accepts A1111 names such as `DPM++ 2M` or ComfyUI
	  names such as `dpmpp_2m`. Empty by default, which respects the client value.
- `A1111_API_SCHEDULER` (optional)
	- Forces a ComfyUI scheduler such as `karras`, `normal`, or `exponential`.
	  Empty by default, which respects a client value or a suffix such as
	  `DPM++ 2M Karras`.
- `A1111_API_PROMPT_MODE` (optional, default `comfy`)
	- Uses native `CLIPTextEncode`, including explicit weights such as
	  `(bright:1.8)`, so API requests match an equivalent basic ComfyUI workflow.
	  Set to `a1111` to opt into A1111-specific conditioning semantics.
- `A1111_API_PROMPT_NORMALIZATION` (optional, default `true`)
	- Enables A1111-style mean normalization for weighted prompts. Set to
	  `false` for A1111 “No norm” behavior, which may suit some SDXL models.
- `A1111_API_LOG_PROMPTS` (optional, default `false`)
	- Logs the exact positive and negative prompts received through the A1111
	  API. Enable temporarily for troubleshooting; prompts may contain private
	  conversation details.
- `WATCHTOWER` (optional, default `false`): controls the `com.centurylinklabs.watchtower.enable` label; set to `true` to allow Watchtower detection when used.
- `CUSTOM_LABEL` (optional, default `foo=bar`): additional label value you can use for whatever reason. Remember, you can only define one single label, no more.

## Included custom nodes

- `ComfyUI-Manager` is installed automatically.
- `comfyui_a1111_api` is installed automatically and provides basic A1111 API
  compatibility.
- `ComfyUI-KJNodes` remains optional and can be enabled with `COMPOSE_PROFILES=kjnodes`.

## AUTOMATIC1111-compatible API

Point A1111-compatible clients at the same URL as ComfyUI, for example
`http://server:8188`. The shim currently provides:

- `POST /sdapi/v1/txt2img`
- `GET /sdapi/v1/sd-models`
- `GET /sdapi/v1/samplers`
- `GET /sdapi/v1/schedulers`
- `GET` and `POST /sdapi/v1/options`
- `GET /sdapi/v1/loras`, `/upscalers`, `/embeddings`, and `/cmd-flags`
- `GET /sdapi/v1/progress`
- `POST /sdapi/v1/interrupt`

Example:

```bash
curl -X POST http://localhost:8188/sdapi/v1/txt2img \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"a lighthouse in a storm","steps":20,"width":512,"height":512}'
```

The response uses the A1111 `images`, `parameters`, and `info` shape, with
generated images returned as base64-encoded PNG data. The compatibility layer
supports prompts, negative prompts, dimensions, steps, CFG scale, seeds,
batching, clip skip, and common A1111 sampler/scheduler names. Each request logs
its resolved parameters without logging the prompt text. Optional A1111 prompt mode
supports explicit weights such as `(bright:1.8)`, shorthand emphasis, `BREAK`,
scheduling, and alternation using the bundled
[`ComfyUI-A1111-cond`](https://github.com/Enferlain/ComfyUI-A1111-cond) node.
It does not currently implement
`img2img`, high-resolution fix, ControlNet, scripts, or every A1111 setting.

## Manual usage example

```bash
export COMFYUI_PATH=/srv/comfyui
export COMFYUI_GPU_DEVICE_ID=0
export COMFYUI_PORT=8188
docker compose up -d
```

For Portainer: create a stack from this Git repo and set the same environment variables in the stack settings.

## Troubleshooting

If `ComfyUI-Manager` shows an error like:

```text
[Installation Errors] 'comfyui_controlnet_aux': This action is not allowed with this security level configuration.
```

the manager is running with a restrictive `security_level`. With this compose file:

- a fresh deployment will automatically create a manager config with `security_level = normal`
- an existing config is left alone unless you set `COMFYUI_MANAGER_SECURITY_LEVEL`

To override it explicitly, set for example:

```bash
export COMFYUI_MANAGER_SECURITY_LEVEL=normal
docker compose up -d
```

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
