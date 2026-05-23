#!/usr/bin/env python3
import os
import re
import sys
import json
import subprocess
import requests
from datetime import datetime

# Path inside the Docker container
SETTINGS_PATH = "/config/settings.conf"
LOG_DIR = "/config/logs"
LOG_FILE = os.path.join(LOG_DIR, "Lidarr-YouTubeMusicAutomator.log")

def log(message):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_line = f"{timestamp} :: Lidarr-YouTubeMusicAutomator :: {message}\n"
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

def sanitize_name(name):
    # Replaces characters that are illegal or unsafe on Windows/Linux filesystems
    return re.sub(r'[\\/*?:"<>|]', "_", str(name)).strip()

def run_download(artist, album, track_num, track_title, output_dir, cookies_path):
    import shutil
    temp_download_dir = "/tmp/yt_download"
    if os.path.exists(temp_download_dir):
        try:
            shutil.rmtree(temp_download_dir)
        except Exception:
            pass
    os.makedirs(temp_download_dir, exist_ok=True)
    
    # Pad track number
    track_num_padded = str(track_num).zfill(2)
    sanitized_title = sanitize_name(track_title)
    
    # Download to temporary directory first
    temp_output_template = os.path.join(temp_download_dir, f"{track_num_padded} - {sanitized_title}.%(ext)s")
    search_query = f"ytsearch1:{artist} - {track_title}"
    
    log(f"Starting download: {artist} - {track_title} (Track {track_num_padded})")
    
    cmd = [
        "yt-dlp",
        "-f", "ba[ext=m4a]/ba",
        "-o", temp_output_template,
        "--extract-audio",
        "--audio-format", "m4a",
        "--no-playlist",
        "--embed-metadata",
        "--embed-thumbnail",
        "--progress",
        "--js-runtimes", "node",
        "--remote-components", "ejs:github",
        search_query
    ]
    
    if os.path.exists(cookies_path):
        temp_cookies_path = "/tmp/cookies.txt"
        try:
            shutil.copy2(cookies_path, temp_cookies_path)
            os.chmod(temp_cookies_path, 0o666)
            cmd.extend(["--cookies", temp_cookies_path])
        except Exception as e:
            log(f"WARNING: Failed to copy cookies to temp location: {e}. Falling back to original.")
            cmd.extend(["--cookies", cookies_path])
    else:
        log(f"WARNING: Cookies file not found at {cookies_path}, proceeding without cookies...")
        
    try:
        result = subprocess.run(cmd, check=True)
        
        # Once successfully downloaded, find the file in temp_download_dir and move it to final output_dir
        os.makedirs(output_dir, exist_ok=True)
        expected_filename = f"{track_num_padded} - {sanitized_title}.m4a"
        temp_file_path = os.path.join(temp_download_dir, expected_filename)
        final_file_path = os.path.join(output_dir, expected_filename)
        
        puid = int(os.environ.get("PUID", 1000))
        pgid = int(os.environ.get("PGID", 1000))
        
        if os.path.exists(temp_file_path):
            shutil.move(temp_file_path, final_file_path)
            try:
                os.chown(final_file_path, puid, pgid)
                os.chmod(final_file_path, 0o666)
            except Exception as pe:
                log(f"WARNING: Failed to set ownership on {final_file_path}: {pe}")
            log(f"Successfully downloaded and moved to destination: {expected_filename}")
            return True
        else:
            # Fallback if filename matched differently
            files = [f for f in os.listdir(temp_download_dir) if f.endswith(".m4a")]
            if files:
                found_file = os.path.join(temp_download_dir, files[0])
                shutil.move(found_file, final_file_path)
                try:
                    os.chown(final_file_path, puid, pgid)
                    os.chmod(final_file_path, 0o666)
                except Exception as pe:
                    log(f"WARNING: Failed to set ownership on {final_file_path}: {pe}")
                log(f"Successfully downloaded and moved to destination (fallback match): {expected_filename}")
                return True
            else:
                log(f"ERROR: Download completed but no .m4a file found in temp directory!")
                return False
    except subprocess.CalledProcessError as e:
        log(f"ERROR downloading track '{track_title}': yt-dlp exited with non-zero status.")
        return False
    finally:
        # Cleanup temp directory
        try:
            shutil.rmtree(temp_download_dir, ignore_errors=True)
        except Exception:
            pass

def main():
    log("Starting YouTube Music Automator execution loop...")
    
    # 1. Load Settings
    settings = load_settings(SETTINGS_PATH)
    
    enabled = settings.get("enableLidarrYouTubeMusicAutomator", "false").lower() == "true"
    if not enabled:
        log("YouTube Music Automator is disabled in settings.conf. Exiting.")
        sys.exit(0)
        
    lidarr_url = settings.get("lidarrUrl", "http://lidarr:8686").rstrip('/')
    lidarr_api_key = settings.get("lidarrApiKey", "")
    cookies_path = settings.get("youtubeCookiesPath", "/config/cookies.txt")
    download_base = settings.get("youtubeDownloadPath", "/downloads/youtube")
    
    if not lidarr_api_key:
        log("ERROR: lidarrApiKey is missing in settings.conf! Exiting.")
        sys.exit(1)
        
    # 2. Get wanted/missing albums from Lidarr
    log("Fetching wanted/missing albums list from Lidarr...")
    url = f"{lidarr_url}/api/v1/wanted/missing?page=1&pagesize=100&apikey={lidarr_api_key}"
    try:
        response = requests.get(url, timeout=30)
        response.raise_for_status()
        missing_data = response.json()
    except Exception as e:
        log(f"ERROR connecting to Lidarr API: {e}")
        sys.exit(1)
        
    records = missing_data.get("records", [])
    log(f"Found {len(records)} missing album(s) to process.")
    
    for album in records:
        artist_name = album.get("artist", {}).get("artistName", "Unknown Artist")
        album_title = album.get("title", "Unknown Album")
        album_id = album.get("id")
        
        log(f"--- Processing Album: {artist_name} - {album_title} (ID: {album_id}) ---")
        
        # 3. Get track list for the album
        track_url = f"{lidarr_url}/api/v1/track?albumId={album_id}&apikey={lidarr_api_key}"
        try:
            track_response = requests.get(track_url, timeout=30)
            track_response.raise_for_status()
            tracks = track_response.json()
        except Exception as e:
            log(f"ERROR fetching tracks for album {album_id}: {e}")
            continue
            
        # Filter for missing tracks (hasFile is False)
        missing_tracks = [t for t in tracks if not t.get("hasFile", False)]
        log(f"Album has {len(tracks)} total tracks. {len(missing_tracks)} are missing and need downloading.")
        
        if not missing_tracks:
            log("No missing tracks for this album. Skipping.")
            continue
            
        album_complete_dir = os.path.join(download_base, "complete", f"{sanitize_name(artist_name)} - {sanitize_name(album_title)}")
        
        downloaded_any = False
        for track in missing_tracks:
            track_num = track.get("trackNumber", "0")
            track_title = track.get("title", "Unknown Track")
            
            success = run_download(
                artist=artist_name,
                album=album_title,
                track_num=track_num,
                track_title=track_title,
                output_dir=album_complete_dir,
                cookies_path=cookies_path
            )
            if success:
                downloaded_any = True
                
        # 4. Trigger Lidarr scan if any tracks were successfully downloaded
        if downloaded_any:
            log(f"Finished downloads for {artist_name} - {album_title}. Triggering Lidarr import scan...")
            cmd_url = f"{lidarr_url}/api/v1/command?apikey={lidarr_api_key}"
            payload = {
                "name": "DownloadedAlbumsScan",
                "path": album_complete_dir
            }
            try:
                cmd_response = requests.post(cmd_url, json=payload, timeout=30)
                cmd_response.raise_for_status()
                log(f"Successfully triggered scan command for path: {album_complete_dir}")
            except Exception as e:
                log(f"ERROR triggering Lidarr scan: {e}")
        else:
            log(f"No tracks were successfully downloaded for {artist_name} - {album_title}.")

    log("Execution loop completed.")

if __name__ == "__main__":
    main()
