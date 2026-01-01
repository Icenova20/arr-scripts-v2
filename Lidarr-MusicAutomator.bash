#!/usr/bin/with-contenv bash
scriptVersion="1.6"
scriptName="Lidarr-MusicAutomator"
dockerPath="/config/logs"
arrApp="Lidarr"
searchOrder="releaseDate"
searchDirection="descending"
deemixFolder="/root/.config/deemix"

settings () {
  log "Import Script $1 Settings..."
  source "$1"
  arrUrl="$lidarrUrl"
  arrApiKey="$lidarrApiKey"
}

verifyConfig () {

	if [ "$enableLidarrMusicAutomator" != "true" ]; then
		log "Script is not enabled, enable by setting enableLidarrMusicAutomator to \"true\" by modifying the \"/config/<filename>.conf\" config file..."
		log "Sleeping (infinity)"
		sleep infinity
	fi

}

InstallDependencies () {
  if apk --no-cache list | grep installed | grep python3 | read; then
    log "Dependencies already installed, skipping..."
  else
    log "Installing script dependencies...."
    apk add  -U --update --no-cache \
      jq \
      xq \
      git \
      opus-tools \
      python3 \
      py3-pip
    log "done"
    python3 -m pip install deemix streamrip pyxDamerauLevenshtein --upgrade --break-system-packages
  fi
}

ArlSetup () {
    if [ -z "$arl" ]; then
        log "ERROR :: ARL Key is missing!"
        log "ERROR :: Please correct for script to continue running..."
        log "ERROR :: Exiting..."
        exit
    fi
    if [ -d "$deemixFolder" ]; then
        log "Creating Deemix Config folder"
        mkdir -p "$deemixFolder"
    fi
    if [ -f "$deemixFolder/.arl" ]; then
        log "Deleting ARL"
        rm "$deemixFolder/.arl"
    fi
    if [ ! -f "$deemixFolder/.arl" ]; then
        log "Creating ARL file"
        echo -n "$arl" > "$deemixFolder/.arl"
        chmod 777 "$deemixFolder/.arl"
    fi

    if [ -f "/config/config/config.json" ]; then
        if [ -f "$deemixFolder/config.json" ]; then
          log "Importing custom deemix config"
          rm "$deemixFolder/config.json"
          cp "/config/config/config.json" "$deemixFolder/config.json"
          chmod 777 "$deemixFolder/config.json"
        fi
    fi
}


logfileSetup () {
  logFileName="$scriptName-$(date +"%Y_%m_%d_%I_%M_%p").txt"

  if find "$dockerPath" -type f -iname "$scriptName-*.txt" | read; then
    # Keep only the last 2 log files for 3 active log files at any given time...
    rm -f $(ls -1t $dockerPath/$scriptName-* | tail -n +5)
    # delete log files older than 5 days
    find "$dockerPath" -type f -iname "$scriptName-*.txt" -mtime +5 -delete
  fi
  
  if [ ! -f "$dockerPath/$logFileName" ]; then
    echo "" > "$dockerPath/$logFileName"
    chmod 666 "$dockerPath/$logFileName"
  fi
}

log () {
  m_time=`date "+%F %T"`
  echo $m_time" :: $scriptName (v$scriptVersion) :: "$1
}

ArrWaitForTaskCompletion () {
  log "$processNumber of $lidarrTotalRecords :: $lidarrAlbumArtistName :: $lidarrAlbumTitle :: Checking $arrApp App Status"
  alerted="no"
  until false
  do
    taskCount=$(curl -s "$arrUrl/api/v1/command?apikey=${arrApiKey}" | jq -r '.[] | select(.status=="started") | .name' | wc -l)
    arrRefreshMonitoredDownloadTaskCount=$(curl -s "$arrUrl/api/v3/command?apikey=${arrApiKey}" | jq -r '.[] | select(.status=="started") | .name' | grep "RefreshMonitoredDownloads" | wc -l)
    if [ "$taskCount" -ge 3 ]; then
      if [ "$alerted" == "no" ]; then
        alerted="yes"
        log "$processNumber of $lidarrTotalRecords :: $lidarrAlbumArtistName :: $lidarrAlbumTitle :: STATUS :: $arrApp APP BUSY :: Pausing/waiting for all active Arr app tasks to end..."
        log "$processNumber of $lidarrTotalRecords :: $lidarrAlbumArtistName :: $lidarrAlbumTitle :: STATUS :: $arrApp APP BUSY :: Waiting..."
      fi
    else
      break
    fi
  done
  log "$processNumber of $lidarrTotalRecords :: $lidarrAlbumArtistName :: $lidarrAlbumTitle :: STATUS :: Done"
}

VerifyApiAccess () {
  log "Step - Verifying $arrApp API is accessible"
  alerted="no"
  until false
  do
    arrApiTest=""
    arrApiVersion=""
    if [ -z "$arrApiTest" ]; then
      arrApiVersion="v3"
      arrApiTest="$(curl -s "$arrUrl/api/$arrApiVersion/system/status?apikey=$arrApiKey" | jq -r .instanceName)"
    fi
    if [ -z "$arrApiTest" ]; then
      arrApiVersion="v1"
      arrApiTest="$(curl -s "$arrUrl/api/$arrApiVersion/system/status?apikey=$arrApiKey" | jq -r .instanceName)"
    fi
    if [ ! -z "$arrApiTest" ]; then
      break
    else
      if [ "$alerted" == "no" ]; then
        alerted="yes"
        log "STATUS :: $arrApp is not ready, sleeping until valid response..."
      fi
      sleep 1
    fi
  done
  log "STATUS :: Done"
}

SearchDeezerAlbums () {
    log "$processNumber of $lidarrTotalRecords :: $lidarrAlbumArtistName :: $lidarrAlbumTitle :: Searching $3 Deezer $2 Albums for a potential match...."
    for deezerAlbumId in $(echo "$1"); do
        deezerAlbumData=$(echo "$getDeezerArtistAlbums" | jq -r ".data[] | select(.id==$deezerAlbumId)")
        deezerAlbumTitle="$(echo "$deezerAlbumData" | jq -r .title)"
        deezerExplicitLyrics="$(echo "$deezerAlbumData" | jq -r .explicit_lyrics)"
        deezerAlbumTitleClean="$(echo "$deezerAlbumTitle" | sed 's/[^0-9A-Za-z]*//g')"
        deezerAlbumReleaseDate="$(echo "$deezerAlbumData" | jq -r .release_date)"
        deezerAlbumYear="${deezerAlbumReleaseDate:0:4}"
        downloadAlbumFolderName="$lidarrAlbumArtistName - $deezerAlbumTitle ($deezerAlbumYear)"

        if [ -f "$completedSearchIdLocation/deezer-$deezerAlbumId" ]; then
            log "$processNumber of $lidarrTotalRecords :: $lidarrAlbumArtistName :: $lidarrAlbumTitle :: Previously Downloaded from Deezer, skipping..."
            continue
        fi

        if echo "${lidarrAlbumTitleClean,,}" | grep "${deezerAlbumTitleClean,,}" | read; then
          diff=$(python -c "from pyxdameraulevenshtein import damerau_levenshtein_distance; print(damerau_levenshtein_distance(\"${lidarrAlbumTitleClean,,}\", \"${deezerAlbumTitleClean,,}\"))" 2>/dev/null) 
        else
          continue
        fi    
        if [ $diff = 0 ]; then
            log "$processNumber of $lidarrTotalRecords :: $lidarrAlbumArtistName :: $lidarrAlbumTitle :: $deezerAlbumTitle :: $deezerAlbumTitleClean vs $lidarrAlbumTitleClean :: Explicit Lyrics ($deezerExplicitLyrics) :: diff $diff :: Match Found!"

            if [ -d "$incompleteDownloadPath" ]; then
                rm -rf "$incompleteDownloadPath"
            fi

            if [ ! -d "$completeDownloadPath/$downloadAlbumFolderName" ]; then
                # delete temporary download location if needed
                if [ ! -d "$incompleteDownloadPath" ]; then
                    mkdir -p "$incompleteDownloadPath"
                fi

                # download tracks
                deemix -p "$incompleteDownloadPath" -b flac "https://www.deezer.com/en/album/$deezerAlbumId"
                
                # Create import location
                if [ ! -d "$completeDownloadPath" ]; then
                    mkdir -p "$completeDownloadPath"
                    chmod 777 -R "$completeDownloadPath"
                fi

                # Create import location album folder
                if [ ! -d "$completeDownloadPath/$downloadAlbumFolderName" ]; then
                    mkdir -p "$completeDownloadPath/$downloadAlbumFolderName"
                fi

                # Move downloaded files to import location album folder
                mv "$incompleteDownloadPath"/* "$completeDownloadPath/$downloadAlbumFolderName"/

                # set permissions
                if [ -d "$completeDownloadPath/$downloadAlbumFolderName" ]; then
                    chmod 777 -R "$completeDownloadPath/$downloadAlbumFolderName"
                fi
            fi

            log "$processNumber of $lidarrTotalRecords :: $lidarrAlbumArtistName :: $lidarrAlbumTitle :: Notifying Lidarr to Import \"$downloadAlbumFolderName\""
            LidarrProcessIt=$(curl -s "$arrUrl/api/v1/command" --header "X-Api-Key:"${arrApiKey} -H "Content-Type: application/json" --data "{\"name\":\"DownloadedAlbumsScan\", \"path\":\"$completeDownloadPath/$downloadAlbumFolderName\"}")
            touch /config/found

            if [ ! -d "$completedSearchIdLocation" ]; then
                mkdir -p "$completedSearchIdLocation"
                chmod 777 -R "$completedSearchIdLocation"
            fi

            if [ -d "$completedSearchIdLocation" ]; then
                touch "$completedSearchIdLocation/deezer-$deezerAlbumId"
                chmod 777 "$completedSearchIdLocation/deezer-$deezerAlbumId"
            fi

            break
        else
            # For debugging only...
            # log "$processNumber of $lidarrTotalRecords :: $lidarrAlbumArtistName :: $lidarrAlbumTitle :: ERROR :: $lidarrAlbumTitle vs $deezerAlbumTitle :: Failed to match, different by: $diff"
            sleep 0.01
        fi
    done

}

LidarrWantedSearch () {
    lidarrTotalRecords=$(echo "$1" | jq -r .totalRecords)
    lidarrWantedIds=$(echo "$1" | jq -r '.records[].id')
    processNumber=0
    for lidarrAlbumId in $(echo "$lidarrWantedIds"); do
        processNumber=$(( $processNumber + 1 ))
        lidarrAlbumData="$(curl -s "$arrUrl/api/v1/album/$lidarrAlbumId?apikey=${arrApiKey}")"
        lidarrAlbumArtistData=$(echo "${lidarrAlbumData}" | jq -r ".artist")
        lidarrAlbumArtistName=$(echo "${lidarrAlbumArtistData}" | jq -r ".artistName")
        lidarrAlbumArtistForeignArtistId=$(echo "${lidarrAlbumArtistData}" | jq -r ".foreignArtistId")
        lidarrAlbumType=$(echo "$lidarrAlbumData" | jq -r ".albumType")
        lidarrAlbumTitle=$(echo "$lidarrAlbumData" | jq -r ".title")
        lidarrAlbumTitleClean="$(echo "$lidarrAlbumTitle" | sed 's/[^0-9A-Za-z]*//g')"
        lidarrAlbumForeignAlbumId=$(echo "$lidarrAlbumData" | jq -r ".foreignAlbumId")
        tidalArtistUrl=$(echo "${lidarrAlbumArtistData}" | jq -r ".links | .[] | select(.name==\"tidal\") | .url")
        tidalArtistIds="$(echo "$tidalArtistUrl" | grep -o '[[:digit:]]*' | sort -u)"
        deezerArtistUrl=$(echo "${lidarrAlbumArtistData}" | jq -r ".links | .[] | select(.name==\"deezer\") | .url")
        deezerArtistIds="$(echo "$deezerArtistUrl" | grep -o '[[:digit:]]*' | sort -u)"
        

        if [ -f "$completedSearchIdLocation/lidarr-$lidarrAlbumId" ]; then
            log "$processNumber of $lidarrTotalRecords :: $lidarrAlbumArtistName :: $lidarrAlbumTitle :: Previously Searched Deezer, skipping..."
            continue
        fi

        for deezerArtistId in $(echo "$deezerArtistIds"); do
            # Uncomment for debugging purposes
            # log "$processNumber of $lidarrTotalRecords :: $lidarrAlbumArtistName :: $lidarrAlbumTitle :: $lidarrAlbumForeignAlbumId :: $deezerArtistId"
            getDeezerArtistAlbums=$(curl -s "https://api.deezer.com/artist/$deezerArtistId/albums?limit=1000")

            if [ "$lidarrAlbumType" = "Single" ]; then
              getDeezerArtistAlbumsExplicitIds="$(echo "$getDeezerArtistAlbums" | jq -r '.data[] | select(.explicit_lyrics==true) | select(.record_type=="single") | .id')"
              getDeezerArtistAlbumsCleanIds="$(echo "$getDeezerArtistAlbums" | jq -r '.data[] | select(.explicit_lyrics==false) |  select(.record_type=="single")| .id')"
            else
              getDeezerArtistAlbumsExplicitIds="$(echo "$getDeezerArtistAlbums" | jq -r '.data[] | select(.explicit_lyrics==true) | .id')"
              getDeezerArtistAlbumsCleanIds="$(echo "$getDeezerArtistAlbums" | jq -r '.data[] | select(.explicit_lyrics==false) | .id')"
            fi
            getDeezerArtistAlbumsCount="$(echo "$getDeezerArtistAlbums" | jq -r .total)"
            getDeezerArtistAlbumsExplicitIdsCount=$(echo "$getDeezerArtistAlbumsExplicitIds" | wc -l)
            getDeezerArtistAlbumsCleanIdsCount=$(echo "$getDeezerArtistAlbumsCleanIds" | wc -l)
            
            if [ -f /config/found ]; then
                rm /config/found
            fi

            # begin explicit search
            SearchDeezerAlbums "$getDeezerArtistAlbumsExplicitIds" "Explicit" "$getDeezerArtistAlbumsExplicitIdsCount"

            if [ ! -f /config/found ]; then
                # begin clean search
                SearchDeezerAlbums "$getDeezerArtistAlbumsCleanIds" "Clean" "$getDeezerArtistAlbumsCleanIdsCount"
            fi

            if [ -f /config/found ]; then
                rm /config/found
                ArrWaitForTaskCompletion
            else
                log "$processNumber of $lidarrTotalRecords :: $lidarrAlbumArtistName :: $lidarrAlbumTitle :: No match found :("
            fi
        done

        if [ ! -d "$completedSearchIdLocation" ]; then
            mkdir -p "$completedSearchIdLocation"
            chmod 777 -R "$completedSearchIdLocation"
        fi

        if [ -d "$completedSearchIdLocation" ]; then
            touch "$completedSearchIdLocation/lidarr-$lidarrAlbumId"
            chmod 777 "$completedSearchIdLocation/lidarr-$lidarrAlbumId"
        fi
    done

}

for (( ; ; )); do
  let i++
  logfileSetup
  touch "$dockerPath/$logFileName"
  exec &> >(tee -a "$dockerPath/$logFileName")
  log "Starting..."
  InstallDependencies
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

    if [ ! -z "$arrUrl" ]; then
      if [ ! -z "$arrApiKey" ]; then
        SECONDS=0        
        VerifyApiAccess
        ArlSetup

        log "Step - Removing previously downloaded items that failed to import..."
        if [ -d "$completeDownloadPath" ]; then
            rm -rf "$completeDownloadPath"/*
        fi

        log "Step - Begining Missing search!"
        lidarrMissingRecords=$(wget --timeout=0 -q -O - "$arrUrl/api/v1/wanted/missing?page=1&pagesize=999999&sortKey=$searchOrder&sortDirection=$searchDirection&apikey=${arrApiKey}")
        LidarrWantedSearch "$lidarrMissingRecords"

        log "Step - Begining Cutoff search!"
        lidarrCutoffRecords=$(wget --timeout=0 -q -O - "$arrUrl/api/v1/wanted/cutoff?page=1&pagesize=999999&sortKey=$searchOrder&sortDirection=$searchDirection&apikey=${arrApiKey}")
        LidarrWantedSearch "$lidarrCutoffRecords"

        duration=$SECONDS
        durationOutput="$(printf '%dd:%dh:%dm:%ds\n' $((duration/86400)) $((duration%86400/3600)) $((duration%3600/60)) $((duration%60)))"
        echo "Completed in $durationOutput!"
        
      else
        log "ERROR :: Skipping $arrApp, missing API Key..."
      fi
    else
      log "ERROR :: Skipping $arrApp, missing URL..."
    fi


  done

  log "Sleeping $lidarrMusicAutomatorScriptInterval..."
  sleep $lidarrMusicAutomatorScriptInterval

done


exit
