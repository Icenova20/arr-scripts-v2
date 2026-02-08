#!/usr/bin/with-contenv bash
scriptVersion="1.0"
scriptName="ScoreCleaner"
dockerLogPath="/config/logs"

settings () {
  log "Import Script $1 Settings..."
  source "$1"
}

verifyConfig () {
	if [ "$enableScoreCleaner" != "true" ]; then
		log "Script is not enabled, enable by setting enableScoreCleaner to \"true\" by modifying the \"/config/<filename>.conf\" config file..."
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
    rm -f $(ls -1t $dockerLogPath/$scriptName-* | tail -n +5)
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

ScoreCleanerProcess () {
  arrApp="$1"

  # Sonarr
  if [ "$arrApp" = "sonarr" ]; then
    arrUrl="$sonarrUrl"
    arrApiKey="$sonarrApiKey"
    arrApiVersion="v3"
    arrQueueData=$(curl -s "$arrUrl/api/$arrApiVersion/queue?page=1&pagesize=200&sortDirection=descending&sortKey=progress&includeUnknownSeriesItems=true&apikey=${arrApiKey}")
  fi

  # Radarr
  if [ "$arrApp" = "radarr" ]; then
    arrUrl="$radarrUrl"
    arrApiKey="$radarrApiKey"
    arrApiVersion="v3"
    arrQueueData=$(curl -s "$arrUrl/api/$arrApiVersion/queue?page=1&pagesize=200&sortDirection=descending&sortKey=progress&includeUnknownMovieItems=true&apikey=${arrApiKey}")
  fi

  # 1. Deduplication (Queue vs Queue)
  log "$arrApp :: Checking for duplicates in queue..."
  
  if [ "$arrApp" = "radarr" ]; then
    entityIds=$(echo "$arrQueueData" | jq -r '.records[].movieId' | sort -u)
  else
    entityIds=$(echo "$arrQueueData" | jq -r '.records[].episodeId' | sort -u)
  fi

  for entityId in $entityIds; do
    if [ "$arrApp" = "radarr" ]; then
      items=$(echo "$arrQueueData" | jq -c ".records[] | select(.movieId==$entityId)")
    else
      items=$(echo "$arrQueueData" | jq -c ".records[] | select(.episodeId==$entityId)")
    fi
    
    count=$(echo "$items" | wc -l)
    if [ "$count" -gt 1 ]; then
      log "$arrApp :: Found $count versions of entity $entityId in queue. Keeping highest score..."
      highestScore=$(echo "$items" | jq -r '.customFormatScore // 0' | sort -rn | head -n 1)
      keepId=$(echo "$items" | jq -s "map(select(.customFormatScore == $highestScore)) | sort_by(.sizeleft) | .[0].id")
      
      for qId in $(echo "$items" | jq -r ".id"); do
        if [ "$qId" != "$keepId" ]; then
          itemTitle=$(echo "$items" | jq -r "select(.id==$qId) | .title")
          itemScore=$(echo "$items" | jq -r "select(.id==$qId) | .customFormatScore // 0")
          log "$arrApp :: $itemTitle ($qId) :: Score ($itemScore) < Highest in Queue ($highestScore). Removing..."
          if [ "$dryRun" = "true" ]; then
            log "$arrApp :: DRY RUN :: Skipping deletion"
          else
            curl -sX DELETE "$arrUrl/api/$arrApiVersion/queue/$qId?removeFromClient=$removeFromClient&blocklist=$blocklist&skipRedownload=$skipRedownload&changeCategory=false&apikey=${arrApiKey}" > /dev/null
          fi
        fi
      done
    fi
  done

  # 2. Upgrade Check (Queue vs Disk)
  log "$arrApp :: Checking queue vs disk scores..."
  for queueId in $(echo "$arrQueueData" | jq -r ".records[].id"); do
    itemData=$(echo "$arrQueueData" | jq -c ".records[] | select(.id==$queueId)")
    if [ -z "$itemData" ]; then continue; fi
    
    queueScore=$(echo "$itemData" | jq -r '.customFormatScore // 0')
    queueItemTitle=$(echo "$itemData" | jq -r .title)

    if [ "$arrApp" = "radarr" ]; then
      movieId=$(echo "$itemData" | jq -r .movieId)
      movieInfo=$(curl -s "$arrUrl/api/v3/movie/$movieId?apikey=$arrApiKey")
      if [ "$(echo "$movieInfo" | jq -r .hasFile)" = "true" ]; then
        existingScore=$(echo "$movieInfo" | jq -r '.movieFile.customFormatScore // 0')
        if [ "$queueScore" -lt "$existingScore" ]; then
          log "$arrApp :: $queueItemTitle ($queueId) :: Queue Score ($queueScore) < On-Disk Score ($existingScore). Removing..."
          if [ "$dryRun" = "true" ]; then
            log "$arrApp :: DRY RUN :: Skipping deletion"
          else
            curl -sX DELETE "$arrUrl/api/$arrApiVersion/queue/$queueId?removeFromClient=$removeFromClient&blocklist=$blocklist&skipRedownload=$skipRedownload&changeCategory=false&apikey=${arrApiKey}" > /dev/null
          fi
        fi
      fi
    fi

    if [ "$arrApp" = "sonarr" ]; then
      episodeId=$(echo "$itemData" | jq -r .episodeId)
      episodeInfo=$(curl -s "$arrUrl/api/v3/episode/$episodeId?apikey=$arrApiKey")
      if [ "$(echo "$episodeInfo" | jq -r .hasFile)" = "true" ]; then
        episodeFileId=$(echo "$episodeInfo" | jq -r .episodeFileId)
        fileInfo=$(curl -s "$arrUrl/api/v3/episodefile/$episodeFileId?apikey=$arrApiKey")
        existingScore=$(echo "$fileInfo" | jq -r '.customFormatScore // 0')
        if [ "$queueScore" -lt "$existingScore" ]; then
          log "$arrApp :: $queueItemTitle ($queueId) :: Queue Score ($queueScore) < On-Disk Score ($existingScore). Removing..."
          if [ "$dryRun" = "true" ]; then
            log "$arrApp :: DRY RUN :: Skipping deletion"
          else
            curl -sX DELETE "$arrUrl/api/$arrApiVersion/queue/$queueId?removeFromClient=$removeFromClient&blocklist=$blocklist&skipRedownload=$skipRedownload&changeCategory=false&apikey=${arrApiKey}" > /dev/null
          fi
        fi
      fi
    fi
  done
}

for (( ; ; )); do
  logfileSetup
  log "Starting..."
  confFiles=$(find /config -mindepth 1 -type f -name "*.conf")
  for f in $confFiles; do
    log "Processing \"$f\""
    settings "$f"
    verifyConfig
    [ ! -z "$radarrUrl" ] && [ ! -z "$radarrApiKey" ] && ScoreCleanerProcess "radarr"
    [ ! -z "$sonarrUrl" ] && [ ! -z "$sonarrApiKey" ] && ScoreCleanerProcess "sonarr"
  done
  log "Sleeping $queueCleanerScriptInterval..."
  sleep $scoreCleanerScriptInterval
done
