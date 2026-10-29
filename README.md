# ComfyUI Docker Image & Compose

This repository provides a ready-to-use Docker image and a `docker-compose.yml` for running ComfyUI with Nvidia GPU support. The image is built from the official upstream repository at https://github.com/Comfy-Org/ComfyUI and is updated automatically by a GitHub Actions workflow whenever new upstream changes are detected.

`ComfyUI-Manager` is included as part of the package. The image bundles it for direct `docker run` usage, and the compose startup command will clone it into the persistent `custom_nodes` volume automatically if it is missing.

The image targets modern NVIDIA GPUs (RTX 20 series and newer) with Python 3.12,
PyTorch 2.10, and CUDA 12.6 wheels. ComfyUI async weight offloading uses its
upstream default. Both local and CI builds follow upstream's default branch and
the latest published workflow templates. CI resolves and pins these inputs before
building. A plain local build resolves them during the build, and Docker rechecks
the remote Git source and template release metadata even when using its cache.

CI also checks PyPI for new `comfyui-workflow-templates` releases independently
of ComfyUI changes. The detected version is installed after the other image
dependencies and checked for a nonempty template catalog. The image labels
`upstream.sha` and `templates.version` record the selected source and templates.
Use `COMFYUI_BRANCH` for a specific branch/tag, `COMFYUI_SHA` for an exact commit,
and `COMFYUI_TEMPLATES_VERSION` for a specific template package version. These are
optional overrides for testing older versions.

Build locally with the same defaults as CI:

```bash
docker build -t comfyui:local .
```

To test the same ComfyUI source and templates as an already published image,
read its labels and pass both versions explicitly. This avoids selecting updates
published since that image was built:

```bash
docker pull ghcr.io/dam-pav/comfyui:latest
COMFYUI_TEST_SHA=$(docker image inspect ghcr.io/dam-pav/comfyui:latest \
  --format '{{ index .Config.Labels "upstream.sha" }}')
COMFYUI_TEST_TEMPLATES=$(docker image inspect ghcr.io/dam-pav/comfyui:latest \
  --format '{{ index .Config.Labels "templates.version" }}')
docker build -t comfyui:local \
  --build-arg COMFYUI_SHA="$COMFYUI_TEST_SHA" \
  --build-arg COMFYUI_TEMPLATES_VERSION="$COMFYUI_TEST_TEMPLATES" .
```

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
- `COMFYUI_UPDATE_CUSTOM_NODES` (optional, default `true`)
  - Fast-forwards installed custom-node Git repositories at each
    container startup, including their example workflows, before installing
    their requirements. Locally modified checkouts, detached revisions, disabled
    nodes, and branches without an upstream are skipped. Update failures stop
    startup and appear in the container logs. Startup changes to the shared
    custom-node volume are serialized across GPU containers. Set to `false` to
    disable automatic custom-node updates.
- `COMFYUI_MANAGER_SECURITY_LEVEL` (optional)
	- Overrides the `ComfyUI-Manager` `security_level` written to the persistent user config.
	- If not set and no manager config exists yet, the compose startup creates one with `security_level = normal`, which matches the current recommended Manager default and allows registered node installs, updates, and restarts.
	- If you already have a manager config, it is preserved unless this variable is explicitly set.
	- The compose startup writes `user/__manager/config.ini`, which is the current protected Manager config path.
- `COMFYUI_LOG_API_REQUESTS` (optional, default `false`)
	- Logs the complete native ComfyUI prompt graph received by `/prompt`,
	  including node types and all inputs such as prompts, models, seeds,
	  dimensions, steps, CFG, samplers, and schedulers. Enable it temporarily for
	  troubleshooting because prompts may contain private conversation details.
- `WATCHTOWER` (optional, default `false`): controls the `com.centurylinklabs.watchtower.enable` label; set to `true` to allow Watchtower detection when used.
- `CUSTOM_LABEL` (optional, default `foo=bar`): additional label value you can use for whatever reason. Remember, you can only define one single label, no more.

## Included custom nodes

- `ComfyUI-Manager` is installed automatically.
- `comfyui_native_api_logging` provides optional native API request logging.
- `ComfyUI-KJNodes` remains optional and can be enabled with `COMPOSE_PROFILES=kjnodes`.

## Native API request logging

To inspect exactly what a native ComfyUI client submits, enable logging and
recreate the container:

```bash
export COMFYUI_LOG_API_REQUESTS=true
docker compose up -d --force-recreate
```

Each `/prompt` request is logged as one JSON record prefixed with
`[ComfyUI API]`. Disable the option after troubleshooting to avoid retaining
potentially private prompt text in container logs.

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

The daily build checks both the ComfyUI commit and the published template package
version. A change to either triggers a build; a manual GitHub Actions run also
requests a build when both are unchanged. The selected commit and template version
are build arguments, so Docker's cache cannot reuse older source or template layers.

After publishing, pull and recreate the container to load the new image:

```bash
docker compose pull comfyui
docker compose up -d comfyui
```

Official templates come from the image's Python environment. Example workflows
from custom nodes come from the persistent `custom_nodes` folder, so pulling an
image alone does not update them. Clean node repositories update automatically
on startup. Set `COMFYUI_UPDATE_CUSTOM_NODES=false` to manage updates manually.
Recreate all GPU containers that share the folder after updating custom nodes.

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
