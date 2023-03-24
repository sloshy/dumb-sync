#!/usr/bin/env bash
# COPYRIGHT 2023 Ryan Peters
# This script version is licensed for your use via the terms of LGPL v3
# See: https://github.com/sloshy/dumb-sync/LICENSE

set -e

LOCAL_DIR=$1
RM_FILES=$2
SUDOPASS=$(cat -)

LOCAL_DIR_CLEAN=${LOCAL_DIR%/}

echo "$SUDOPASS" | sudo -S docker run --rm -v "$LOCAL_DIR_CLEAN/:/tmp/images/:rw" marctv/chd-converter

if [[ "$RM_FILES" = "true" ]]; then
  rm -f "$LOCAL_DIR_CLEAN"/*.bin
  rm -f "$LOCAL_DIR_CLEAN"/*.cue
  rm -f "$LOCAL_DIR_CLEAN"/*.gdi
  rm -f "$LOCAL_DIR_CLEAN"/*.iso
fi
