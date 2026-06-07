#!/usr/bin/with-contenv bash
scriptVersion="1.0"
scriptName="Sonarr-AnimeSeriesAutoType"
dockerPath="/config"
settingsFile="/config/settings.conf"

log () {
  m_time=`date "+%F %T"`
  echo "$m_time :: $scriptName (v$scriptVersion) :: $1"
}

logfileSetup () {
  logFileName="$scriptName-$(date +"%Y_%m_%d_%I_%M_%p").txt"
  mkdir -p "$dockerPath/logs"
  
  if find "$dockerPath/logs" -type f -iname "$scriptName-*.txt" | read; then
    # Keep only the last 3 log files
    rm -f $(ls -1t $dockerPath/logs/$scriptName-* | tail -n +4)
    # delete log files older than 5 days
    find "$dockerPath/logs" -type f -iname "$scriptName-*.txt" -mtime +5 -delete
  fi
  
  if [ ! -f "$dockerPath/logs/$logFileName" ]; then
    echo "" > "$dockerPath/logs/$logFileName"
    chown ${PUID:-1000}:${PGID:-1000} "$dockerPath/logs/$logFileName"
    chmod 666 "$dockerPath/logs/$logFileName"
  fi
}

# Daemon Loop
for (( ; ; )); do
  logfileSetup
  # Redirect output to log file and console
  exec &> >(tee -a "$dockerPath/logs/$logFileName")
  
  log "Starting execution cycle..."
  
  # Load interval from settings
  if [ -f "$settingsFile" ]; then
    source "$settingsFile"
  fi
  
  if [ "$enableSonarrAnimeSeriesAutoType" != "true" ]; then
    log "Sonarr Anime Auto-Type is disabled in settings.conf, sleeping indefinitely..."
    sleep infinity
  fi
  
  # Run the Python core engine
  python3 "/config/Sonarr-AnimeSeriesAutoType.py"
  
  interval=${sonarrAnimeSeriesAutoTypeInterval:-"12h"}
  log "Cycle complete. Sleeping for $interval..."
  sleep $interval
done
