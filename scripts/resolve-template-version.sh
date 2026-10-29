#!/bin/bash
set -euo pipefail

# Share PyPI release selection and validation between CI and Docker builds.
python3 - "$@" <<'PY'
import json
import re
import sys
import urllib.request

if len(sys.argv) > 1:
    with open(sys.argv[1]) as release:
        package = json.load(release)
else:
    url = "https://pypi.org/pypi/comfyui-workflow-templates/json"
    with urllib.request.urlopen(url, timeout=30) as release:
        package = json.load(release)

version = package["info"]["version"]
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
    raise SystemExit(f"Unexpected template version: {version!r}")
if not any(not artifact.get("yanked", False) for artifact in package["urls"]):
    raise SystemExit("Template release has no usable distribution")
print(version)
PY
