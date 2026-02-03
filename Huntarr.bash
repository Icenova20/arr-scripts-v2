#!/usr/bin/with-contenv bash
scriptVersion="1.2"
scriptName="Huntarr"
dockerLogPath="/config/logs"

settings () {
  log "Import Script $1 Settings..."
  source "$1"
}

verifyConfig () {

	if [ "$enableHuntarr" != "true" ]; then
		log "Script is not enabled, enable by setting enableHuntarr to \"true\" by modifying the \"/config/<filename>.conf\" config file..."
		log "Sleeping (infinity)"
		sleep infinity
	fi

}

logfileSetup () {
  logFileName="$scriptName-$(date +"%Y_%m_%d_%I_%M_%p").txt"

  if [ ! -d "$dockerLogPath" ]; then
    mkdir -p "$dockerLogPath"
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
    chmod 666 "$dockerLogPath/$logFileName"
  fi
}

log () {
  m_time=`date "+%F %T"`
  echo $m_time" :: $scriptName (v$scriptVersion) :: "$1
  echo $m_time" :: $scriptName (v$scriptVersion) :: "$1 >> "$dockerLogPath/$logFileName"
}

HuntarrRadarr () {
    arrApp="Radarr"
    arrUrl="$radarrUrl"
    arrApiVersion="v3"
    arrApiKey="$radarrApiKey"
}

HuntarrSonarr () {
    arrApp="Sonarr"
    arrUrl="$sonarrUrl"
    arrApiVersion="v3"
    arrApiKey="$sonarrApiKey"    
}

ArrAppStatusCheck () {
    arrQueue=$(curl -s "$arrUrl/api/$arrApiVersion/queue?page=1&pageSize=100&apikey=${arrApiKey}")
    arrQueueTotalRecords=$(echo "$arrQueue" | jq -r '.records[] | select(.status!="completed") | .id' | wc -l)
    if [ $arrQueueTotalRecords -ge 3 ]; then
        touch "/config/huntarr-break"
        return
    fi
    arrTaskCount=$(curl -s "$arrUrl/api/$arrApiVersion/command?apikey=${arrApiKey}" | jq -r '.[] | select(.status=="started") | .name' | wc -l)
    if [ $arrTaskCount -ge 3 ]; then
        touch "/config/huntarr-break"
        return
    fi

}

HuntarrProcess () {
    # Create base directory for various functions/process
    if [ ! -d "/config/huntarr" ]; then
        mkdir -p "/config/huntarr" 
    fi

    # Reset API count if older than 1 day
    if [ -f "/config/huntarr/$arrApp-api-search-count" ]; then
        find "/config/huntarr" -iname "$arrApp-api-search-count" -type f -mtime +1 -delete
    else
        echo -n "0" > "/config/huntarr/$arrApp-api-search-count"
    fi

    # check if API limit has been reached
    if [ -f "/config/huntarr/$arrApp-api-search-count" ]; then
        currentApiCounter=$(cat "/config/huntarr/$arrApp-api-search-count")
        if [ $currentApiCounter -ge $huntarrDailyApiSearchLimit ]; then
            log "$arrApp :: Daily API Limit reached... "
            return
        fi
    fi

    # Check if Arr application is too busy...
    if [ -f "/config/huntarr-break" ]; then
        rm "/config/huntarr-break"
    fi
    ArrAppStatusCheck
    if [ -f "/config/huntarr-break" ]; then
        rm "/config/huntarr-break"
        log "$arrApp App busy..."
        return
    fi

    # delete cached lists if older than 6 hours
    find "/config/huntarr" -iname "$arrApp-*-list.json" -type f -mmin +360 -delete

    # Gather Missing and Cutoff items for processing...
    searchOrder="releaseDate"
    searchDirection="descending"
    if [ ! -f "/config/huntarr/$arrApp-missing-list.json" ]; then
        wget --timeout=0 -q -O - "$arrUrl/api/$arrApiVersion/wanted/missing?page=1&pagesize=999999&sortKey=&sortDirection=$searchDirection&apikey=${arrApiKey}" | jq -r '.records[]' > "/config/huntarr/$arrApp-missing-list.json"
    fi
    
    if [ ! -f "/config/huntarr/$arrApp-cutoff-list.json" ]; then
        wget --timeout=0 -q -O - "$arrUrl/api/$arrApiVersion/wanted/cutoff?page=1&pagesize=999999&sortKey=$searchOrder&sortDirection=$searchDirection&apikey=${arrApiKey}" | jq -r '.records[]' > "/config/huntarr/$arrApp-cutoff-list.json"
    fi

    arrItemListData=$(cat  "/config/huntarr/$arrApp-missing-list.json" "/config/huntarr/$arrApp-cutoff-list.json")
    arrItemIds=$(echo "$arrItemListData" | jq -r .id)
    arrItemCount=$(echo "$arrItemIds" | wc -l) 

    # Begin Processing Missing and Cutoff items
    processNumber=0
    for arrItemId in $(echo "$arrItemIds"); do
        processNumber=$(($processNumber + 1))

        # check if API limit has been reached
        if [ -f "/config/huntarr/$arrApp-api-search-count" ]; then
            currentApiCounter=$(cat "/config/huntarr/$arrApp-api-search-count")
            if [ $currentApiCounter -ge $huntarrDailyApiSearchLimit ]; then
                log "$arrApp :: $processNumber/$arrItemCount :: Daily API Limit reached..."
                break
            fi
        fi

        # Check for previous search
        if [ -f "/config/huntarr/$settingsFileName/$arrApp/$arrItemId" ]; then
            log "$arrApp :: $processNumber/$arrItemCount :: Previously Searched ($arrItemId), skipping..."
            continue
        fi

        # Check if Arr application is too busy...
        ArrAppStatusCheck
        if [ -f "/config/huntarr-break" ]; then
            rm "/config/huntarr-break"
            log "$arrApp :: $processNumber/$arrItemCount :: $arrApp App busy..."
            return
        fi   

        # Perform Search
        arrItemData=$(echo "$arrItemListData" | jq -r "select(.id==$arrItemId)")
        arrItemTitle=$(echo "$arrItemData" | jq -r .title)
        
        log "$arrApp :: $processNumber/$arrItemCount :: $arrItemTitle ($arrItemId) :: Searching..."

        if [ "$arrApp" == "Radarr" ]; then
            automatedSearchTrigger=$(curl -s "$arrUrl/api/$arrApiVersion/command" -X POST -H 'Content-Type: application/json' -H "X-Api-Key: $arrApiKey" --data-raw "{\"name\":\"MoviesSearch\",\"movieIds\":[$arrItemId]}")
        fi

        if [ "$arrApp" == "Sonarr" ]; then
            automatedSearchTrigger=$(curl -s "$arrUrl/api/$arrApiVersion/command" -X POST -H 'Content-Type: application/json' -H "X-Api-Key: $arrApiKey" --data-raw "{\"name\":\"EpisodeSearch\",\"episodeIds\":[$arrItemId]}")
        fi

        # update API search count
        echo -n "$(($currentApiCounter + 1))" > "/config/huntarr/$arrApp-api-search-count"

        # create log folder for searched items
        if [ ! -d "/config/huntarr/$settingsFileName/$arrApp" ]; then
            mkdir -p "/config/huntarr/$settingsFileName/$arrApp"
        fi

        # create log of searched item
        if [ ! -f "/config/huntarr/$settingsFileName/$arrApp/$arrItemId" ]; then
            touch "/config/huntarr/$settingsFileName/$arrApp/$arrItemId"
        fi        
    done
}


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
    settingsFileName=$(basename "${f%.*}")
    settings "$f"
    verifyConfig
    if [ ! -z "$radarrUrl" ]; then
      if [ ! -z "$radarrApiKey" ]; then
        HuntarrRadarr
        HuntarrProcess
      else
        log "ERROR :: Skipping Radarr, missing API Key..."
      fi
    else
      log "ERROR :: Skipping Radarr, missing URL..."
    fi
    if [ ! -z "$sonarrUrl" ]; then
      if [ ! -z "$sonarrApiKey" ]; then
        HuntarrSonarr
        HuntarrProcess
      else
        log "ERROR :: Skipping Sonarr, missing API Key..."
      fi
    else
      log "ERROR :: Skipping Sonarr, missing URL..."
    fi
  done

  log "Sleeping $huntarrScriptInterval..."
  sleep $huntarrScriptInterval

done

exit
