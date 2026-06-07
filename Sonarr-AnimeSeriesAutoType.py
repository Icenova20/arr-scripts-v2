#!/usr/bin/env python3
import os
import re
import sys
import json
import urllib.request
from datetime import datetime

# Path inside the Docker container
SETTINGS_PATH = "/config/settings.conf"
LOG_DIR = "/config/logs"
LOG_FILE = os.path.join(LOG_DIR, "Sonarr-AnimeSeriesAutoType.log")

def log(message):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_line = f"{timestamp} :: Sonarr-AnimeSeriesAutoType :: {message}\n"
    print(log_line.strip(), flush=True)
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
        with open(LOG_FILE, "a") as f:
            f.write(log_line)
    except Exception as e:
        print(f"Error writing to log file: {e}", flush=True)

def load_settings(path):
    settings = {}
    if not os.path.exists(path):
        log(f"WARNING: Configuration file not found at {path}")
        return settings
    
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            # Match variable_name="value" or variable_name=value
            match = re.match(r"^([a-zA-Z0-9_]+)\s*=\s*\"([^\"]*)\"", line)
            if match:
                settings[match.group(1)] = match.group(2)
            else:
                match = re.match(r"^([a-zA-Z0-9_]+)\s*=\s*([^\s#]+)", line)
                if match:
                    settings[match.group(1)] = match.group(2)
    return settings

def api_get(url, api_key, endpoint):
    req = urllib.request.Request(
        f"{url}{endpoint}",
        headers={"X-Api-Key": api_key, "Accept": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())

def api_put(url, api_key, endpoint, data):
    req = urllib.request.Request(
        f"{url}{endpoint}",
        data=json.dumps(data).encode('utf-8'),
        headers={"X-Api-Key": api_key, "Content-Type": "application/json", "Accept": "application/json"},
        method="PUT"
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())

def main():
    log("Starting Sonarr Anime Auto-Type scan...")
    
    # 1. Load Settings
    settings = load_settings(SETTINGS_PATH)
    
    enabled = settings.get("enableSonarrAnimeSeriesAutoType", "false").lower() == "true"
    if not enabled:
        log("Sonarr Anime Auto-Type is disabled in settings.conf. Exiting.")
        sys.exit(0)
        
    sonarr_url = settings.get("sonarrUrl", "http://sonarr:8989").rstrip('/')
    sonarr_api_key = settings.get("sonarrApiKey", "")
    
    if not sonarr_api_key:
        log("ERROR: sonarrApiKey is missing in settings.conf! Exiting.")
        sys.exit(1)
        
    # 2. Get all series from Sonarr
    log("Fetching series list from Sonarr...")
    try:
        series_list = api_get(sonarr_url, sonarr_api_key, "/api/v3/series")
    except Exception as e:
        log(f"ERROR: Failed to connect to Sonarr API: {e}")
        sys.exit(1)
        
    updated_count = 0
    for series in series_list:
        is_standard = series.get("seriesType") == "standard"
        genres = series.get("genres", [])
        is_anime_genre = "Anime" in genres
        
        if is_standard and is_anime_genre:
            title = series.get("title", f"ID: {series.get('id')}")
            log(f"Detected misclassified anime: '{title}' (ID: {series['id']})")
            series["seriesType"] = "anime"
            
            try:
                api_put(sonarr_url, sonarr_api_key, f"/api/v3/series/{series['id']}", series)
                updated_count += 1
                log(f"Successfully updated '{title}' to Anime type.")
            except Exception as e:
                log(f"ERROR: Failed to update '{title}': {e}")
                
    log(f"Scan complete. Automatically converted {updated_count} series to the Anime type.")

if __name__ == "__main__":
    main()
