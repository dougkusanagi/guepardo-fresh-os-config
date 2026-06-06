#!/usr/bin/env bash

for installer in "$INSTALL_ROOT"/desktop/*.sh; do
  # shellcheck source=/dev/null
  source "$installer"
done
