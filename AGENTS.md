# AGENTS.md - Repository Guide for Agentic Coding

This repository is a Docker-focused project that builds and distributes ComfyUI containers. The codebase consists primarily of Docker configuration, CI/CD workflows, and documentation.

## Project Overview

This repository provides:
- Automated Docker image builds from upstream ComfyUI
- Docker Compose templates for deployment
- GitHub Actions CI/CD pipeline
- Support for NVIDIA GPU containers
- Optional KJNodes extension management

## Build and Test Commands

### Docker Commands
```bash
# Build the Docker image locally
docker build -t comfyui:local .

# Test the container locally
docker run --rm -it comfyui:local python --version

# Run with docker-compose (requires COMFYUI_PATH env var)
export COMFYUI_PATH=/srv/comfyui
docker compose up -d

# Stop containers
docker compose down

# View logs
docker compose logs -f comfyui
```

### CI/CD Testing
The GitHub Actions workflow (`.github/workflows/build-and-publish.yml`) handles automated testing:
- Builds Docker image on every push to main
- Runs scheduled builds daily
- Tests image functionality via container startup

### Single Test Command
Since this is a Docker project, testing involves container validation:
```bash
# Test container can start and run ComfyUI
docker run --rm --gpus all comfyui:local python main.py --help
```

## Code Style Guidelines

### Dockerfile Style
- Use official base images (`python:3.10-slim`)
- Combine related RUN commands with && to reduce layers
- Use specific versions for pinned dependencies
- Clean up package caches in same RUN command
- Set WORKDIR explicitly
- Use venv for Python dependencies

### Docker Compose Style
- Use version "3.9" syntax
- Environment variables in `${VAR_NAME:-default}` format
- Service names use underscores (snake_case)
- Volume paths use absolute paths from environment variables
- Comments explain required and optional environment variables

### YAML/Configuration Style
- 2-space indentation for YAML files
- Use consistent quoting for strings
- Logical grouping of related settings
- Descriptive comments for complex configurations

### File Organization
```
/
├── Dockerfile                 # Main container definition
├── docker-compose.yml        # Deployment template
├── README.md                 # User documentation
└── .github/workflows/        # CI/CD pipelines
    └── build-and-publish.yml # Automated builds
```

## Environment Variables

### Required
- `COMFYUI_PATH`: Absolute path for ComfyUI data storage

### Optional
- `COMFYUI_GPU_DEVICE_ID`: GPU selection (default: 0)
- `COMFYUI_PORT`: Host port mapping (default: 8188)
- `COMPOSE_PROFILES`: Set to "kjnodes" for KJNodes init container

## Dependencies

### Docker Images
- Base: `python:3.10-slim`
- Upstream: `https://github.com/Comfy-Org/ComfyUI.git`
- Runtime: NVIDIA container runtime for GPU support

### Python Packages
- PyTorch with CUDA support (pinned versions)
- ComfyUI requirements from upstream
- Additional dependencies for common extensions:
  - diffusers
  - gitpython
  - opencv-python-headless
  - av
  - imageio-ffmpeg
  - toml

## Error Handling

### Docker Build Errors
- Check network connectivity for git clones
- Verify base image availability
- Validate Python package versions

### Runtime Errors
- Ensure GPU drivers are installed for NVIDIA containers
- Verify volume permissions on host
- Check port availability for COMFYUI_PORT

### CI/CD Failures
- Monitor upstream ComfyUI repository changes
- Verify GitHub Actions runner permissions
- Check container registry authentication

## Security Practices

- Use multi-stage builds where appropriate
- Run containers as non-root users when possible
- Don't include secrets in Docker images
- Use read-only filesystems when feasible
- Keep base images updated

## Common Tasks

### Updating ComfyUI Version
The workflow automatically tracks upstream changes. Manual updates require modifying the `COMFYUI_BRANCH` argument in Dockerfile.

### Adding New Dependencies
1. Add to Dockerfile RUN instruction
2. Update documentation in README.md
3. Test container build and functionality

### Modifying GPU Support
Update the `gpus:` section in docker-compose.yml based on Docker version and NVIDIA runtime configuration.

## Repository-Specific Notes

- This is a distribution repository, not a development repository
- Source code is pulled from upstream during build
- Focus is on containerization and deployment best practices
- Automated builds ensure fresh images from upstream changes
- KJNodes extension is optionally supported via init container