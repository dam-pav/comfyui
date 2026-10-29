#!/bin/bash
set -euo pipefail

# Shared custom_nodes volumes may be used by multiple GPU containers. Serialize
# updates, including dependency installation, in the compose startup command.
if [ "${COMFYUI_UPDATE_CUSTOM_NODES:-true}" != "true" ]; then
  exit 0
fi

for node_dir in "${1:-/opt/ComfyUI/custom_nodes}"/*; do
  # Check for a repository at this exact path, not a parent ComfyUI checkout.
  if [ ! -d "$node_dir/.git" ] && [ ! -f "$node_dir/.git" ]; then
    continue
  fi
  case "$node_dir" in
    *.disabled) continue ;;
  esac

  if [ -n "$(git -C "$node_dir" status --porcelain)" ]; then
    echo ">>> Skipping locally modified custom node: $node_dir"
    continue
  fi
  if ! git -C "$node_dir" symbolic-ref -q HEAD >/dev/null; then
    echo ">>> Skipping pinned custom node: $node_dir"
    continue
  fi
  if ! git -C "$node_dir" rev-parse --verify '@{upstream}' >/dev/null 2>&1; then
    echo ">>> Skipping custom node without a tracking branch: $node_dir"
    continue
  fi

  echo ">>> Updating custom node and example workflows: $node_dir"
  git -C "$node_dir" pull --ff-only
done
