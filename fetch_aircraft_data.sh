#!/bin/bash

SERVER="root@138.68.117.49"
REMOTE_DIR="/home/jetclock-v2/data-app"
REMOTE_FILE="aircraft-backup.json"
API_URL="https://opendata.adsb.fi/api/v2/snapshot"
LOCAL_TEMP_FILE="/tmp/aircraft_temp.json"

transform_data() {
    local input_file="$1"
    local output_file="$2"
    
    python3 -c "
import json
import sys
from datetime import datetime

try:
    with open('$input_file', 'r') as f:
        data = json.load(f)
    
    transformed = {}
    
    for aircraft in data:
        hex_id = aircraft.get('hex', '').upper()
        if not hex_id or hex_id.startswith('~'):
            continue
            
        last_pos = aircraft.get('lastPosition', {})
        if not last_pos:
            continue
            
        lat = last_pos.get('lat')
        lng = last_pos.get('lon') 
        
        if lat is None or lng is None:
            continue
            
        transformed[hex_id] = {
            'icao': hex_id,
            'lat': lat,
            'lng': lng,
            'altitude': aircraft.get('alt_baro', 0) if aircraft.get('alt_baro') != 'ground' else 0,
            'speed': aircraft.get('gs', 0),
            'heading': aircraft.get('track', 0),
            'callsign': aircraft.get('r', '').strip(),
            'lastUpdated': datetime.utcnow().isoformat() + 'Z'
        }
    
    with open('$output_file', 'w') as f:
        json.dump(transformed, f, indent=2)
        
except Exception as e:
    print(f'Error transforming data: {e}', file=sys.stderr)
    sys.exit(1)
"
}

fetch_and_upload() {
    echo "$(date): Fetching aircraft data..."
    
    # Fetch data from API
    if ! curl -s -o "$LOCAL_TEMP_FILE" "$API_URL"; then
        echo "$(date): Error: Failed to fetch data from API"
        return 1
    fi
    
    # Check if file was created and has content
    if [ ! -s "$LOCAL_TEMP_FILE" ]; then
        echo "$(date): Error: No data received from API"
        return 1
    fi
    
    # Transform the data
    local transformed_file="/tmp/aircraft_transformed.json"
    if ! transform_data "$LOCAL_TEMP_FILE" "$transformed_file"; then
        echo "$(date): Error: Failed to transform data"
        return 1
    fi
    
    # Upload to server
    if ! scp "$transformed_file" "$SERVER:$REMOTE_DIR/$REMOTE_FILE"; then
        echo "$(date): Error: Failed to upload to server"
        return 1
    fi
    
    echo "$(date): Successfully updated aircraft-backup.json"
    
    # Cleanup
    rm -f "$LOCAL_TEMP_FILE" "$transformed_file"
    return 0
}

# Main loop
echo "Starting aircraft data fetcher..."
echo "Will fetch data every 31 seconds and upload to $SERVER:$REMOTE_DIR/$REMOTE_FILE"

while true; do
    fetch_and_upload
    echo "$(date): Waiting 31 seconds..."
    sleep 31
done