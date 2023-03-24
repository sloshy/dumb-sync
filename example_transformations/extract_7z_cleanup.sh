#!/usr/bin/env bash
# COPYRIGHT 2023 Ryan Peters
# This script version is licensed for your use via the terms of LGPL v2.1
# See: https://github.com/sloshy/dumb-sync/LICENSE

set -e

OUT_DIR=$1
EXT=$2
RM_FILE=$3

OUT_DIR_CLEAN=${OUT_DIR%/}

#Set default for removing file (true)
[[ "$RM_FILE" = true || "$RM_FILE" = false ]] || RM_FILE="true"

for f in "$OUT_DIR_CLEAN"/*."$EXT"; do
  [[ -f "$f" ]] || break
  7z e "$f" -o"$OUT_DIR"
  if [ $RM_FILE = true ]; then
    rm -f "$f"
  fi
done
