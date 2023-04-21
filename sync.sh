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
  jq -c '.transformations[]' sync.json
  jq -c '.cleanup_transformations[]' sync.json
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
defaultRemoteUrl=$(jq -r '.remote_url' sync.json)

preexistingFilesDir=$(mktemp -d)
trap 'rm -rf -- "$preexistingFilesDir"' EXIT

while read -r obj; do
  remoteUrlName=$(echo "$obj" | jq -r '.url_name')

  if [[ "$remoteUrlName" == "null" ]]; then
    remoteUrl="$defaultRemoteUrl"
    remoteUrlName="(default)"
  else
    while read -r remoteUrlConf; do
      confName=$(echo "$remoteUrlConf" | jq -r '.name')
      if [[ "$confName" == "$remoteUrlName" ]]; then
        remoteUrl=$(echo "$remoteUrlConf" | jq -r '.url')
        break
      fi
    done < <(jq -c '.remote_urls[] // []' sync.json)
  fi

  if [[ "$remoteUrl" == "null" ]]; then
    echo "ERROR: Remote URL not specified. Add a value to the 'remote_url' key in 'sync.json' that is a valid rsync data source (SSH, rsync, another local folder, etc.)"
    exit 1
  fi

  remote=$(echo "$obj" | jq -r '.remote')
  localDirConf=$(echo "$obj" | jq -r '.local')
  localDir=${localDirConf%/}

  disabled=$(echo "$obj" | jq -r '.disabled // false')

  if [[ "$disabled" == "true" ]]; then
    echo "Skipping disabled config (Remote: $remote) (Local: $localDirConf)" | tee -a "$logDir"/last_run.txt
    continue
  fi

  maxSizeBytes=$(echo "$obj" | jq -r '.max_size_bytes')
  minSizeBytes=$(echo "$obj" | jq -r '.min_size_bytes')
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
    # Ensure dollar signs and double quotes are escaped
    # exclEsc=$(echo "$excl" | sed -e "s/\$/\\\$/g" -e "s/\"/\\\"/g")
    exclude="$exclude--exclude=\"$excl\" "
  done < <(echo "$obj" | jq -r '.exclude // [] | .[]')
  while read -r incl; do
    # Ensure dollar signs and double quotes are escaped
    # inclEsc=$(echo "$incl" | sed -e "s/\$/\\\$/g" -e "s/\"/\\\"/g")
    include="$include--include=\"$incl\" "
  done < <(echo "$obj" | jq -r '.include // [] | .[]')

  preexistingFilesList="$preexistingFilesDir"/"$fileListName"
  touch "$preexistingFilesList"

  echo "= = = = = = = = = =" | tee -a "$logDir"/last_run.txt
  echo " " | tee -a "$logDir"/last_run.txt
  echo "Syncing remote ($remoteUrlName -- $remote), To Local: ($localDirConf)" | tee -a "$logDir"/last_run.txt
  mkdir -p "$localDir"
  echo "Transform steps: $transforms" | tee -a "$logDir"/last_run.txt
  echo "Cleanup steps: $cleanups" | tee -a "$logDir"/last_run.txt
  echo "Include args: $include" | tee -a "$logDir"/last_run.txt
  echo "Exclude args: $exclude" | tee -a "$logDir"/last_run.txt
  if [[ "$maxSizeBytes" != "null" ]]; then
    echo "Max size: $maxSizeBytes bytes" | tee -a "$logDir"/last_run.txt
  else
    echo "Max size not specified." | tee -a "$logDir"/last_run.txt
  fi
  if [[ "$minSizeBytes" != "null" ]]; then
    echo "Min size: $minSizeBytes bytes" | tee -a "$logDir"/last_run.txt
  else
    echo "Min size not specified." | tee -a "$logDir"/last_run.txt
  fi
  if [[ "$comparison" == "null" ]] && [[ "$transformCount" -eq 0 ]] && [[ "$cleanupCount" -eq 0 ]] && [[ "$rmMissingFiles" != "true" ]]; then
    echo "Skipping file list (no comparisons, transformations, cleanup, or removals specified)" | tee -a "$logDir"/last_run.txt
  else
    echo "Getting file list..." | tee -a "$logDir"/last_run.txt
    eval "rsync --no-motd --list-only$include$exclude\"$remoteUrl$remote\" \"$localDir/\" 2>&1 | tee -a \"$logDir\"/last_run.txt > \"$fileListDir/$fileListName-file-list.txt\""

    # File list sanity check
    listHead=$(head -n 1 "$fileListDir/$fileListName-file-list.txt")
    fileLineRegex="\b([0-9]{4}/[0-9]{2}/[0-9]{2}) ([0-9]{2}:[0-9]{2}:[0-9]{2}) (.*)\b"
    if ! [[ "$listHead" =~ $fileLineRegex ]]; then
      echo "Error getting file list. See '$fileListDir/$fileListName-file-list.txt' for more details." | tee -a "$logDir"/last_run.txt
      exit 1
    fi

    # File existence / removal check
    if [[ "$comparison" != "null" ]] || [[ "$rmMissingFiles" == "true" ]]; then
      echo "Comparing file list to existing files..." | tee -a "$logDir"/last_run.txt
      fileDel=0

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
                  existFileClean=$(echo "$existFile" | sed -e 's/\"/\\"/g' -e 's/\$/\\$/g')
                  cmd="$cmd \"$existFileClean\""
                  ;;

                "<filename_local_base>")
                  existFileBaseClean=$(echo "$existFileBase" | sed -e 's/\"/\\"/g' -e 's/\$/\\$/g')
                  cmd="$cmd \"$existFileBaseClean\""
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
            # If files are set to be removed, this will be removed later, else included in preexistingFilesList
            ;;
          "current"*)
            # We want to exclude files that are 'current' but probably transformed
            remoteFileName=${cmdResult#current }
            # Ensure dollar signs and double quotes are escaped
            # exclEsc=$(echo "$remoteFileName" | sed -e "s/\$/\\\$/g" -e "s/\"/\\\"/g")
            remoteFileNameClean=$(echo "$remoteFileName" | sed -e 's/\[/\\[/g' -e 's/\]/\\]/g' -e 's/\$/\\$/g')
            if [[ "$remoteFileNameClean" != "$remoteFileName" ]]; then
              echo "File '$remoteFileName' is being excluded from results as '$remoteFileNameClean' due to rsync pattern rules." | tee -a "$logDir"/last_run.txt
            fi
            exclude="$exclude--exclude=\"$remoteFileNameClean\" "
            fileExists=true
            echo "$existFile" >>"$preexistingFilesList"
            ;;
          "updated")
            fileUpdated="true"
            ;;
          "transform")
            fileExists=true
            echo "File '$existFile' is present but not transformed yet. Will transform after sync." | tee -a "$logDir"/last_run.txt
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
          if grep -Fq "$existFileBase" "$fileListDir/$fileListName-file-list.txt"; then
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
          echo "$existFile" >>"$preexistingFilesList"
        fi
      done
      [[ $rmMissingFiles = true ]] && echo "Deleted $fileDel files" | tee -a "$logDir"/last_run.txt
    else
      echo "Skipping file check (no comparison or 'rm_missing' option specified)..." | tee -a "$logDir"/last_run.txt
    fi
  fi

  #Sync
  if [[ "$maxSizeBytes" != "null" ]]; then
    maxSizeArg=" --max-size=\"$maxSizeBytes\""
  else
    maxSizeArg=""
  fi
  if [[ "$minSizeBytes" != "null" ]]; then
    minSizeArg=" --min-size=\"$minSizeBytes\""
  else
    minSizeArg=""
  fi
  eval "rsync -hav$maxSizeArg$minSizeArg$include$exclude\"$remoteUrl$remote/\" \"$localDir/\" | tee -a \"$logDir\"/last_run.txt"

  #Transforms
  [[ "$transformCount" -gt 0 ]] && for f in "$localDir"/*; do
    [[ -f "$f" ]] || break

    # Checks if the file is marked as preexisting and should not be transformed
    if ! grep -Fq "$f" "$preexistingFilesList"; then
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
                fClean=$(echo "$f" | sed -e 's/\"/\\"/g' -e 's/\$/\\$/g')
                cmd="$cmd \"$fClean\""
                ;;

              "<filename_remote_base>")
                basefile=$(basename -- "$f")
                basefileClean=$(echo "$baseFile" | sed -e 's/\"/\\"/g' -e 's/\$/\\$/g')
                cmd="$cmd \"$basefileClean\""
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
            if [[ "${PIPESTATUS[0]}" -gt 0 ]]; then
              exit 1
            fi
          fi
        done < <(jq -c '.transformations[]' sync.json)
      done < <(echo "$obj" | jq -r '.transforms[]')
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
          if [[ "${PIPESTATUS[0]}" -gt 0 ]]; then
            exit 1
          fi
        fi
      done < <(jq -c '.cleanup_transformations[]' sync.json)
    done < <(echo "$obj" | jq -r '.cleanup[]')
  fi
done < <(jq -c '.configs[]' sync.json)

echo "$syncStartTime" >"$logDir/last_run_secs.txt"
