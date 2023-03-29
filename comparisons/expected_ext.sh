#!/usr/bin/env bash
# COPYRIGHT 2023 Ryan Peters
# This script version is licensed for your use via the terms of LGPL v2.1
# See: https://github.com/sloshy/dumb-sync/LICENSE

FILE_LIST=$1
FILE_LOCAL=$2
REMOTE_EXT=$3
LOCAL_EXT=$4
LAST_SYNC_TIME_SECS=$5
SYNC_OFFSET_SECS=$6

FILE_LOCAL_BASE=$(basename -- "$FILE_LOCAL" ".$LOCAL_EXT")

# (Date) (Time) (Filename)
FILE_LINE_REGEX="\b([0-9]{4}/[0-9]{2}/[0-9]{2}) ([0-9]{2}:[0-9]{2}:[0-9]{2}) (.*)\b"
EXPECTED_FILE="$FILE_LOCAL_BASE.$REMOTE_EXT"

set +e
GREP_OUT=$(grep -F "$FILE_LOCAL_BASE.$REMOTE_EXT" "$FILE_LIST")
if [[ "$?" -eq 0 ]]; then
  while read -r FILE_LINE; do
    if [[ "$FILE_LINE" =~ $FILE_LINE_REGEX ]]; then
      FILE_DATE=${BASH_REMATCH[1]}
      FILE_TIME=${BASH_REMATCH[2]}
      FILE_NAME=${BASH_REMATCH[3]}

      [[ "$FILE_NAME" == "$EXPECTED_FILE" ]] || continue

      FILE_SECS=$(date -d "$FILE_DATE $FILE_TIME" +%s)
      FILE_SECS_OFFSET=$((FILE_SECS + SYNC_OFFSET_SECS))
      if [[ "$LAST_SYNC_TIME_SECS" -le "$FILE_SECS_OFFSET" ]]; then
        echo "updated"
        exit 0
      else
        echo "current $FILE_NAME"
        exit 0
      fi
    else
      exit 1
    fi
  done < <(echo "$GREP_OUT")
  # See if the file is just not transformed yet
  BASE_WITHOUT_REMOTE=${FILE_LOCAL_BASE%"$REMOTE_EXT"}
  if grep -Fq "$BASE_WITHOUT_REMOTE" "$FILE_LIST"; then
    echo "transform"
    exit 0
  else
    echo "missing"
    exit 0
  fi
else
  # See if the file is just not transformed yet
  BASE_WITHOUT_REMOTE=${FILE_LOCAL_BASE%"$REMOTE_EXT"}
  if grep -Fq "$BASE_WITHOUT_REMOTE" "$FILE_LIST"; then
    echo "transform"
    exit 0
  else
    echo "missing"
    exit 0
  fi
fi
