#!/bin/bash

set -euo pipefail

# Source environment variables
if [ -f ".env.generator" ]; then
    source .env.generator
else
    echo "Error: .env.generator file not found"
    exit 1
fi

# Check if API key is set
if [ -z "${ELEVENLABS_API_KEY:-}" ]; then
    echo "Error: ELEVENLABS_API_KEY not set in .env.generator"
    exit 1
fi

# Check if start and end times are provided as arguments
if [ -n "$1" ] && [ -n "$2" ]; then
    START_TIME="$1"
    END_TIME="$2"
else
    # Prompt user for start and end times
    read -p "Enter start time (HH:MM:SS): " START_TIME
    read -p "Enter end time (HH:MM:SS): " END_TIME
fi

# Check if VOD link is provided as third argument
if [ -n "$3" ]; then
    VOD_LINK="$3"
else
    # Prompt user for VOD link
    read -p "Enter VOD link: " VOD_LINK
fi

# Validate that times and link are not empty
if [ -z "$START_TIME" ] || [ -z "$END_TIME" ] || [ -z "$VOD_LINK" ]; then
    echo "Error: Start time, end time, and VOD link cannot be empty"
    exit 1
fi

echo "Downloading section from $START_TIME to $END_TIME..."
yt-dlp --extract-audio --audio-format mp3 --download-sections "*${START_TIME}-${END_TIME}" "$VOD_LINK" --output "clever-take-audio.mp3"
echo "Download complete: clever-take-audio.mp3"

echo "Transcribing audio with ElevenLabs..."
RESPONSE=$(curl --progress-bar -X POST https://api.elevenlabs.io/v1/speech-to-text \
     -H "xi-api-key: ${ELEVENLABS_API_KEY}" \
     -H "Content-Type: multipart/form-data" \
     -F model_id="scribe_v1" \
     -F timestamps_granularity="none" \
     -F file=@"clever-take-audio.mp3")

# Extract just the text field and save to file
echo "$RESPONSE" | jq -r '.text' > transcript.txt
echo "Transcription complete. Saved to transcript.txt"



echo cleaning up files
echo Deleting clever-take-audio.mp3
rm clever-take-audio.mp3
echo Deleting transcript.txt
rm transcript.txt
echo "Clean up complete."
