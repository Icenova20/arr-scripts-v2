#!/usr/bin/with-contenv bash
scriptVersion="1.0"
scriptName="Lidarr-YouTubeMusicAutomator"
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

InstallDependencies () {
  # Install system requirements if missing
  if ! command -v python3 &> /dev/null || ! command -v ffmpeg &> /dev/null || ! command -v node &> /dev/null; then
    log "Installing system requirements (python3, pip, ffmpeg, nodejs)..."
    apk add -U --update --no-cache python3 py3-pip ffmpeg nodejs
  fi

  # Verify if requirements are already installed
  if pip3 show yt-dlp >/dev/null 2>&1 && pip3 show requests >/dev/null 2>&1 && pip3 show mutagen >/dev/null 2>&1; then
    log "Dependencies already installed, skipping..."
  else
    log "Installing python script dependencies...."
    python3 -m pip install yt-dlp requests mutagen --upgrade --break-system-packages
    log "done."
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
  
  if [ "$enableLidarrYouTubeMusicAutomator" != "true" ]; then
    log "YouTube Music Automator is disabled in settings.conf, sleeping indefinitely..."
    sleep infinity
  fi
  
  InstallDependencies
  
  # Run the Python core engine
  python3 "/config/Lidarr-YouTubeMusicAutomator.py"
  
  interval=${lidarrYouTubeMusicAutomatorInterval:-"1h"}
  log "Cycle complete. Sleeping for $interval..."
  sleep $interval
done
