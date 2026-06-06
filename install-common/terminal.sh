#!/usr/bin/env bash

for installer in "$INSTALL_ROOT"/terminal/*.sh; do
  # shellcheck source=/dev/null
  source "$installer"
done
