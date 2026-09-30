#!/usr/bin/env bash
set -Eeuo pipefail
cd "${1:?missing repository root}"
# Include every file used by the Linux orchestrator and its profile scripts.
{
  printf '%s\n' install.sh go.mod go.sum
  find cmd scripts install-common install-ubuntu install-fedora -type f
} | LC_ALL=C sort | while IFS= read -r path; do sha256sum "$path"; done | sha256sum | cut -d ' ' -f 1
