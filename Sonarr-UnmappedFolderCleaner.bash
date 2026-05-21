#!/usr/bin/env bash
scriptVersion="1.2"
scriptName="Sonarr-UnmappedFolderCleaner"
dockerLogPath="/config/logs"

settings () {
  log "Import Script $1 Settings..."
  source "$1"
  arrUrl="$sonarrUrl"
  arrApiKey="$sonarrApiKey"
}

logfileSetup () {
  logFileName="$scriptName-$(date +"%Y_%m_%d_%I_%M_%p").txt"

  if [ ! -d "$dockerLogPath" ]; then
    mkdir -p "$dockerLogPath"
    chown ${PUID:-1000}:${PGID:-1000} "$dockerLogPath"
    chmod 777 "$dockerLogPath"
  fi

  if find "$dockerLogPath" -type f -iname "$scriptName-*.txt" | read; then
    # Keep only the last 5 log files for 6 active log files at any given time...
    rm -f $(ls -1t $dockerLogPath/$scriptName-* | tail -n +5)
    # delete log files older than 5 days
    find "$dockerLogPath" -type f -iname "$scriptName-*.txt" -mtime +5 -delete
  fi
  
  if [ ! -f "$dockerLogPath/$logFileName" ]; then
    echo "" > "$dockerLogPath/$logFileName"
    chown ${PUID:-1000}:${PGID:-1000} "$dockerLogPath/$logFileName"
    chmod 666 "$dockerLogPath/$logFileName"
  fi
}

log () {
  m_time=`date "+%F %T"`
  echo "$m_time :: $scriptName (v$scriptVersion) :: $1"
  echo "$m_time :: $scriptName (v$scriptVersion) :: $1" >> "$dockerLogPath/$logFileName"
}

verifyConfig () {

  if [ "$enableUnmappedFolderCleaner" != "true" ]; then
    log "Script is not enabled, enable by setting enableUnmappedFolderCleaner to \"true\" by modifying the \"/config/extended.conf\" config file..."
    log "Sleeping (infinity)"
    sleep infinity
  fi

}

UnmappedFolderCleanerProcess () {
	log "Finding UnmappedFolders to purge..."
	OLDIFS="$IFS"
	IFS=$'\n'
    unmappedFoldersCount=$(curl -s "$arrUrl/api/v3/rootFolder" -H "X-Api-Key: $arrApiKey" | jq -r ".[].unmappedFolders[].path" | wc -l)
	log "$unmappedFoldersCount Folders Found!"
	if [ $unmappedFoldersCount = 0 ]; then 
	    log "No cleanup required, exiting..."
	    return
	fi
    unmappedFoldersData=$(curl -s "$arrUrl/api/v3/rootFolder" -H "X-Api-Key: $arrApiKey" | jq -r '.[] | .path as $root | .unmappedFolders[]? | "\($root)|\(.path)"')
	while IFS= read -r data; do
	    if [ -z "$data" ]; then continue; fi
	    root_path="${data%|*}"
	    folder="${data#*|}"

	    real_root=$(realpath "$root_path" 2>/dev/null) || real_root="$root_path"
	    real_folder=$(realpath "$folder" 2>/dev/null) || real_folder="$folder"

	    if [[ "$real_folder" == "$real_root/"* ]] && [[ "$real_folder" != "$real_root" ]] && [[ "$real_folder" != "/" ]]; then
	        log "Removing $folder"
		    if [ -d "$folder" ]; then
		        rm -rf "${folder:?}"
		    else
			    log "ERROR :: Cannot Delete \"$folder\", directory not found, skipping..."
                log "ERROR :: Check to make sure Sonarr root folder is mapped properly to this container..."
		    fi
	    else
	        log "ERROR :: SECURITY WARNING: \"$folder\" is not a valid sub-directory of \"$root_path\". Skipping deletion."
	    fi
	done <<< "$unmappedFoldersData"
	IFS="$OLDIFS"
 }


# Loop Script
for (( ; ; )); do
	let i++
	logfileSetup
	log "Starting..."
	confFiles=$(find /config -mindepth 1 -type f -name "*.conf")
  confFileCount=$(echo "$confFiles" | wc -l)

  if [ -z "$confFiles" ]; then
      log "ERROR :: No config files found, exiting..."
      exit
  fi

  for f in $confFiles; do
    count=$(($count+1))
    log "Processing \"$f\" config file"
    settings "$f"
    verifyConfig
    if [ -n "$arrUrl" ]; then
      if [ -n "$arrApiKey" ]; then
        UnmappedFolderCleanerProcess
      else
        log "ERROR :: Skipping, missing API Key..."
      fi
    else
      log "ERROR :: Skipping, missing URL..."
    fi
  done
	log "Script sleeping for $unmappedFolderCleanerScriptInterval..."
	sleep $unmappedFolderCleanerScriptInterval
done

exit
