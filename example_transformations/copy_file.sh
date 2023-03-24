#!/usr/bin/env bash
# COPYRIGHT 2023 Ryan Peters
# This script version is licensed for your use via the terms of LGPL v2.1
# See: https://github.com/sloshy/dumb-sync/LICENSE

set -e

IN_FILE=$1
OUT_FILE=$2
OVERWRITE=$3

if [[ "$OVERWRITE" = "true" ]]; then
  rm -f "$IN_FILE"
elif [[ -f "$IN_FILE" ]]; then
  echo "File '$IN_FILE' already exists. Skipping..."
  exit 0
fi

cp "$IN_FILE" "$OUT_FILE"
