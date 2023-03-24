#!/usr/bin/env bash
# COPYRIGHT 2023 Ryan Peters
# This script version is licensed for your use via the terms of LGPL v2.1
# See: https://github.com/sloshy/dumb-sync/LICENSE

set -e

[ -f last_run_old.txt ] && rm last_run_old.txt
[ -f last_run.txt ] && mv last_run.txt last_run_old.txt

[ -f last_run_secs.txt ] || echo "0" >last_run_secs.txt

lastRunSecs=$(cat last_run_secs.txt)
syncStartTime=$(date +%s)

#Detect sudo
needsSudo=false
while read -r obj; do
  needsSudo=$(echo "$obj" | jq -r '.sudo // false')
  [[ "$needsSudo" = "true" ]] && break
done < <(
  jq -c '.transforms[]' sync.json
  jq -c '.cleanup_transforms[]' sync.json
)

if [[ "$needsSudo" == "true" ]]; then
  echo "Sudo requirement detected"
  echo -n "Enter Sudo password: "
  read -rs sudoPass
  echo ""
fi

logDirConf=$(jq -r '.log_dir // "./"' sync.json)
logDir=${logDirConf%/}
fileListDirConf=$(jq -r ".file_list_dir // \"$logDir\"" sync.json)
fileListDir=${fileListDirConf%/}
syncOffset=$(jq -r '.sync_time_offset_seconds // 0' sync.json)
remoteUrl=$(jq -r '.remote_url' sync.json)

if [[ "$remoteUrl" == "null" ]]; then
  echo "ERROR: Remote URL not specified. Add a value to the 'remote_url' key in 'sync.json' that is a valid rsync data source (SSH, rsync, another local folder, etc.)"
  exit 1
fi

while read -r obj; do
  remote=$(echo "$obj" | jq -r '.remote')
  localDirConf=$(echo "$obj" | jq -r '.local')
  localDir=${localDirConf%/}
  fileListName=${localDir//\//_} # Replaces forward slashes with underscores
  transformCount=$(echo "$obj" | jq -r '.transforms // [] | length')
  transforms=$(echo "$obj" | jq -c '.transforms // []' | sed -e 's/\[\]/\(none\)/' -e's/"//g' -e 's/,/ -> /g' -e 's/\[//' -e 's/\]//')
  cleanupCount=$(echo "$obj" | jq -r '.cleanup // [] | length')
  cleanups=$(echo "$obj" | jq -c '.cleanup // []' | sed -e 's/\[\]/\(none\)/' -e's/"//g' -e 's/,/ -> /g' -e 's/\[//' -e 's/\]//')
  comparison=$(echo "$obj" | jq -r '.comparison')
  rmMissingFiles=$(echo "$obj" | jq -r '.rm_missing // false')
  exclude=" "
  include=" "
  while read -r excl; do
    exclude="$exclude--exclude=\"$excl\" "
  done < <(echo "$obj" | jq -r '.exclude // [] | .[]')
  while read -r incl; do
    include="$include--include=\"$incl\" "
  done < <(echo "$obj" | jq -r '.include // [] | .[]')

  echo "= = = = = = = = = =" | tee -a "$logDir"/last_run.txt
  echo " " | tee -a "$logDir"/last_run.txt
  echo "Syncing remote ($remote), To Local: ($localDir)" | tee -a "$logDir"/last_run.txt
  mkdir -p "$localDir"
  echo "Transform steps: $transforms" | tee -a "$logDir"/last_run.txt
  echo "Cleanup steps: $cleanups" | tee -a "$logDir"/last_run.txt
  echo "Include args: $include" | tee -a "$logDir"/last_run.txt
  echo "Exclude args: $exclude" | tee -a "$logDir"/last_run.txt
  echo "Getting file list..." | tee -a "$logDir"/last_run.txt
  eval "rsync --list-only$include$exclude\"$remoteUrl$remote\" \"$localDir/\" 2>&1 | tee -a \"$logDir\"/last_run.txt | tail -n +9 > \"$fileListDir/$fileListName-file-list.txt\""

  # File existence / removal check
  fileDel=0
  declare -A preexistingFiles # Only used/populated for custom comparisons, so these files are skipped by transformations
  for existFile in "$localDir"/*; do
    [[ -f "$existFile" ]] || break
    fileExists=false
    fileUpdated=false
    existFileBase=$(basename -- "$existFile")
    if [ "$comparison" != "null" ]; then
      # Attempt to compare with a user-defined comparison script
      cmd=""
      while read -r compObj; do
        compName=$(echo "$compObj" | jq -r '.name')
        compScript=$(echo "$compObj" | jq -r '.script')

        if [[ "$comparison" == "$compName" ]]; then
          cmd="$compScript"
          while read -r compParam; do
            case $compParam in
            "<outdir>")
              cmd="$cmd \"$localDir\"/"
              ;;

            "<outdir_abs>")
              cmd="$cmd \"$(pwd)/$localDir\""
              ;;

            "<file_list>")
              cmd="$cmd \"$fileListDir/$fileListName-file-list.txt\""
              ;;

            "<filename_local>")
              cmd="$cmd \"$existFile\""
              ;;

            "<filename_local_base>")
              cmd="$cmd \"$existFileBase\""
              ;;

            "<last_sync_time_secs>")
              cmd="$cmd \"$lastRunSecs\""
              ;;

            "<current_time_secs>")
              cmd="$cmd \"$(date +%s)\""
              ;;

            "<sync_offset_secs>")
              cmd="$cmd \"$syncOffset\""
              ;;

            "<arg:"*)
              trueArg=$(echo "$compParam" | sed -e "s/<arg://" -e "s/>//")
              getArg=$(echo "$obj" | jq -r ".$trueArg")
              cmd="$cmd \"$getArg\""
              ;;

            *)
              cmd="$cmd \"$compParam\""
              ;;
            esac
          done < <(echo "$compObj" | jq -r '.params[]')
          break
        fi
      done < <(jq -c '.comparisons[] // []' sync.json)

      if [[ -z "$cmd" ]]; then
        echo "ERROR: Comparison script not found. Exiting..." | tee -a "$logDir"/last_run.txt
        exit 1
      fi

      set +e
      cmdResult=$(eval "$cmd")
      set -e

      case $cmdResult in
      "missing")
        # Do nothing at this time
        # If files are set to be removed, this will be removed later, else included in preexistingFiles
        ;;
      "current")
        # We want to exclude files that are 'current' but probably transformed
        exclude="$exclude--exclude=\"$existFileBase\" "
        fileExists=true
        preexistingFiles["$existFile"]=1
        ;;
      "updated")
        fileUpdated="true"
        ;;
      *)
        echo "Comparison script '$cmd' had invalid response '$cmdResult'. Exiting..." | tee -a "$logDir"/last_run.txt
        exit 1
        ;;
      esac
    elif [[ "$rmMissingFiles" == "true" ]]; then
      # Default comparison logic
      # Saving some cycles by relying on rsync's built-in file updating
      # This means we only need to worry about missing files, as updated files will be handled automatically
      if grep -q "$existFileBase" "$fileListDir/$fileListName-file-list.txt"; then
        fileExists=true
      fi
    fi

    if [[ "$fileExists" == "false" ]] && [[ $rmMissingFiles = true ]]; then
      echo "Deleting nonexistent file: $existFile" | tee -a "$logDir"/last_run.txt
      rm -f "$existFile"
      fileDel=$((fileDel + 1))
    elif [[ "$fileUpdated" == "true" ]]; then
      echo "File $existFile is updated. Deleting and redownloading." | tee -a "$logDir"/last_run.txt
      rm -f "$existFile"
      fileDel=$((fileDel + 1))
    elif [[ "$fileExists" == "false" ]]; then
      # For the case where files are "missing" but present locally, but not set to be removed, they're marked preexisting
      preexistingFiles["$existFile"]=1
    fi
  done
  [[ $rmMissingFiles = true ]] && echo "Deleted $fileDel files" | tee -a "$logDir"/last_run.txt

  #Sync
  eval "rsync -hav$include$exclude\"$remoteUrl$remote/\" \"$localDir/\" | tee -a \"$logDir\"/last_run.txt"

  #Transforms
  [[ "$transformCount" -gt 0 ]] && for f in "$localDir"/*; do
    [[ -f "$f" ]] || break

    # Checks if the file is marked as preexisting and should not be transformed
    if [[ -v preexistingFiles[$f] ]]; then
      while read -r tName; do
        while read -r tObj; do
          name=$(echo "$tObj" | jq -r '.name')
          if [ "$tName" == "$name" ]; then
            script=$(echo "$tObj" | jq -r '.script')
            cmd="$script"
            while read -r param; do
              case $param in
              "<outdir>")
                cmd="$cmd \"$localDir\"/"
                ;;

              "<outdir_abs>")
                cmd="$cmd \"$(pwd)/$localDir\""
                ;;

              "<file_list>")
                cmd="$cmd \"$fileListDir/$fileListName-file-list.txt\""
                ;;

              "<filename_remote>")
                cmd="$cmd \"$f\""
                ;;

              "<filename_remote_base>")
                basefile=$(basename -- "$f")
                cmd="$cmd \"$basefile\""
                ;;

              "<arg:"*)
                trueArg=$(echo "$param" | sed -e "s/<arg://" -e "s/>//")
                getArg=$(echo "$obj" | jq -r ".$trueArg")
                cmd="$cmd \"$getArg\""
                ;;

              "<last_sync_time_secs>")
                cmd="$cmd \"$lastRunSecs\""
                ;;

              "<current_time_secs>")
                cmd="$cmd \"$(date +%s)\""
                ;;

              "<sync_offset_secs>")
                cmd="$cmd \"$syncOffset\""
                ;;

              *)
                cmd="$cmd \"$param\""
                ;;
              esac
            done < <(echo "$tObj" | jq -r '.params[]')

            needsSudo=$(echo "$tObj" | jq -r '.sudo // false')
            [[ "$needsSudo" == "true" ]] && cmd="echo $sudoPass | $cmd"
            eval "$cmd" | tee -a "$logDir"/last_run.txt
          fi
        done < <(jq -c '.transforms[]' sync.json)
      done < <(echo "$obj" | jq -r '.transform[]')
    fi
  done

  #Cleanup
  if [[ "$cleanupCount" -gt 0 ]]; then
    echo "Cleaning up remaining files..." | tee -a "$logDir"/last_run.txt
    while read -r cName; do
      while read -r cObj; do
        name=$(echo "$cObj" | jq -r '.name')
        if [ "$cName" = "$name" ]; then
          script=$(echo "$cObj" | jq -r '.script')
          cmd="$script"
          while read -r param; do
            case $param in
            "<outdir>")
              cmd="$cmd \"$localDir\""
              ;;
            "<outdir_abs>")
              cmd="$cmd \"$(pwd)/$localDir\""
              ;;
            "<file_list>")
              cmd="$cmd \"$fileListDir/$fileListName-file-list.txt\""
              ;;
            "<last_sync_time_secs>")
              cmd="$cmd \"$lastRunSecs\""
              ;;
            "<current_time_secs>")
              cmd="$cmd \"$(date +%s)\""
              ;;
            "<sync_offset_secs>")
              cmd="$cmd \"$syncOffset\""
              ;;
            "<arg:"*)
              trueArg=$(echo "$param" | sed -e "s/<arg://" -e "s/>//")
              getArg=$(echo "$obj" | jq -r ".$trueArg")
              cmd="$cmd \"$getArg\""
              ;;
            *)
              cmd="$cmd \"$param\""
              ;;
            esac
          done < <(echo "$cObj" | jq -r '.params[]')

          needsSudo=$(echo "$cObj" | jq -r '.sudo // false')
          [[ "$needsSudo" = "true" ]] && cmd="echo $sudoPass | $cmd"

          eval "$cmd" | tee -a "$logDir"/last_run.txt
        fi
      done < <(jq -c '.cleanup_transforms[]' sync.json)
    done < <(echo "$obj" | jq -r '.cleanup[]')
  fi
done < <(jq -c '.configs[]' sync.json)

echo "$syncStartTime" >"$logDir/last_run_secs.txt"
