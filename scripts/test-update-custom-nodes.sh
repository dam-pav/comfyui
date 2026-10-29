#!/bin/bash
set -euo pipefail

updater=$(cd "$(dirname "$0")" && pwd)/update-custom-nodes.sh
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com

git init -q -b main "$test_dir/upstream"
mkdir -p "$test_dir/upstream/example_workflows" "$test_dir/nodes"
echo old > "$test_dir/upstream/example_workflows/template.json"
git -C "$test_dir/upstream" add .
git -C "$test_dir/upstream" commit -qm initial
old_sha=$(git -C "$test_dir/upstream" rev-parse HEAD)

for node in clean dirty pinned untracked disabled.disabled diverged; do
  git clone -q "$test_dir/upstream" "$test_dir/nodes/$node"
done
echo local > "$test_dir/nodes/dirty/example_workflows/template.json"
git -C "$test_dir/nodes/pinned" checkout -q --detach
git -C "$test_dir/nodes/untracked" branch --unset-upstream
echo local > "$test_dir/nodes/diverged/local.txt"
git -C "$test_dir/nodes/diverged" add .
git -C "$test_dir/nodes/diverged" commit -qm local
# Keep the divergent checkout out of the first update pass.
mv "$test_dir/nodes/diverged" "$test_dir/diverged"
mkdir "$test_dir/nodes/plain-directory"

echo new > "$test_dir/upstream/example_workflows/template.json"
git -C "$test_dir/upstream" commit -qam updated
new_sha=$(git -C "$test_dir/upstream" rev-parse HEAD)

# An explicit false disables updates.
COMFYUI_UPDATE_CUSTOM_NODES=false bash "$updater" "$test_dir/nodes"
test "$(git -C "$test_dir/nodes/clean" rev-parse HEAD)" = "$old_sha"

# An unset variable enables updates by default.
env -u COMFYUI_UPDATE_CUSTOM_NODES bash "$updater" "$test_dir/nodes"
test "$(git -C "$test_dir/nodes/clean" rev-parse HEAD)" = "$new_sha"
test "$(cat "$test_dir/nodes/clean/example_workflows/template.json")" = new
for node in dirty pinned untracked disabled.disabled; do
  test "$(git -C "$test_dir/nodes/$node" rev-parse HEAD)" = "$old_sha"
done
test "$(cat "$test_dir/nodes/dirty/example_workflows/template.json")" = local

# Diverged branches fail without resetting or merging local commits.
mv "$test_dir/diverged" "$test_dir/nodes/diverged"
diverged_sha=$(git -C "$test_dir/nodes/diverged" rev-parse HEAD)
if COMFYUI_UPDATE_CUSTOM_NODES=true bash "$updater" "$test_dir/nodes"; then
  echo "ERROR: Diverged checkout unexpectedly updated" >&2
  exit 1
fi
test "$(git -C "$test_dir/nodes/diverged" rev-parse HEAD)" = "$diverged_sha"
echo "Custom-node update tests passed"
