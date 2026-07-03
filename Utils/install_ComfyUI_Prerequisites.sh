#!/usr/bin/env bash

# Install the host-side prerequisites needed by docker-compose.yml:
#   * NVIDIA GPU driver
#   * Docker Engine with the Compose plugin
#   * NVIDIA Container Toolkit configured for Docker
#
# Supported distributions: Ubuntu and Debian (x86_64/arm64).
# Run with: sudo ./Utils/installPrerequisites.sh

set -Eeuo pipefail

log() {
  printf '\n>>> %s\n' "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

if [[ ${EUID} -ne 0 ]]; then
  die "Run this script as root (for example: sudo $0)."
fi

[[ -r /etc/os-release ]] || die "Cannot determine the Linux distribution."
# shellcheck disable=SC1091
. /etc/os-release

case "${ID:-}" in
  ubuntu | debian) ;;
  *) die "Unsupported distribution '${ID:-unknown}'. Only Ubuntu and Debian are supported." ;;
esac

case "$(dpkg --print-architecture)" in
  amd64 | arm64) ;;
  *) die "NVIDIA container packages are not configured for this architecture." ;;
esac

export DEBIAN_FRONTEND=noninteractive

log "Installing package-management prerequisites"
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg linux-headers-"$(uname -r)"

if ! command -v lspci >/dev/null 2>&1; then
  apt-get install -y --no-install-recommends pciutils
fi

if ! lspci -d 10de: >/dev/null 2>&1; then
  die "No NVIDIA PCI device was detected."
fi

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  log "A working NVIDIA driver is already installed"
  nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
else
  log "Installing the NVIDIA GPU driver"
  if [[ ${ID} == ubuntu ]]; then
    apt-get install -y --no-install-recommends ubuntu-drivers-common
    ubuntu-drivers install
  else
    # Debian's driver is provided by the contrib/non-free/non-free-firmware
    # components. Give a useful error if the host has not enabled them.
    if ! apt-cache show nvidia-driver >/dev/null 2>&1; then
      die "The Debian 'nvidia-driver' package is unavailable. Enable contrib, non-free, and non-free-firmware in the Debian APT sources, then rerun this script."
    fi
    apt-get install -y nvidia-driver firmware-misc-nonfree
  fi
fi

log "Installing Docker Engine and the Compose plugin"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/${ID}/gpg" \
  | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/%s %s stable\n' \
  "$(dpkg --print-architecture)" "${ID}" "${VERSION_CODENAME}" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

log "Installing the NVIDIA Container Toolkit"
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#' \
  > /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update
apt-get install -y nvidia-container-toolkit

log "Configuring Docker's NVIDIA runtime"
nvidia-ctk runtime configure --runtime=docker
systemctl enable --now docker
systemctl restart docker

if nvidia-smi >/dev/null 2>&1; then
  log "Validating GPU access from Docker"
  docker run --rm --gpus all ubuntu:24.04 nvidia-smi
  log "Prerequisites installed successfully"
else
  log "Installation finished, but the new NVIDIA kernel driver is not active yet"
  printf '%s\n' \
    "Reboot the host, then verify it with:" \
    "  nvidia-smi" \
    "  docker run --rm --gpus all ubuntu:24.04 nvidia-smi"
fi
