#!/usr/bin/env bash
# COPYRIGHT 2023 Ryan Peters
# This script version is licensed for your use via the terms of LGPL v2.1
# See: https://github.com/sloshy/dumb-sync/LICENSE

set -e

IN_FILE=$1
OUT_DIR=$2
RM_FILE=$3
OVERWRITE=$4

#Set default for removing file (true)
[[ "$RM_FILE" = true || "$RM_FILE" = false ]] || RM_FILE="true"

EXTRA_CMD=""

if [[ "$OVERWRITE" == "true" ]]; then
  EXTRA_CMD="-aoa "
fi

7z e "$IN_FILE" $EXTRA_CMD-o"$OUT_DIR"

if [ $RM_FILE = true ]; then
  rm -f "$IN_FILE"
fi
