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

# Check if only a link is provided (single argument) or if times are provided too
if [ -n "$1" ] && [ -z "$2" ]; then
    # Only link provided, process entire video
    VOD_LINK="$1"
    START_TIME=""
    END_TIME=""
    echo "Processing entire video"
elif [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ]; then
    # Times and link provided
    START_TIME="$1"
    END_TIME="$2"
    VOD_LINK="$3"
else
    # Prompt user for input
    read -p "Enter VOD link: " VOD_LINK
    read -p "Enter start time (HH:MM:SS) [leave blank to process entire video]: " START_TIME
    read -p "Enter end time (HH:MM:SS) [leave blank to process entire video]: " END_TIME
fi

# Validate that link is not empty
if [ -z "$VOD_LINK" ]; then
    echo "Error: VOD link cannot be empty"
    exit 1
fi

if [ -n "$START_TIME" ] && [ -n "$END_TIME" ]; then
    echo "Downloading section from $START_TIME to $END_TIME..."
    yt-dlp --extract-audio --audio-format mp3 --download-sections "*${START_TIME}-${END_TIME}" "$VOD_LINK" --output "clever-take-audio.mp3"
else
    echo "Downloading entire VOD..."
    yt-dlp --extract-audio --audio-format mp3 "$VOD_LINK" --output "clever-take-audio.mp3"
fi
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

# Read the transcript for the article
TRANSCRIPT=$(cat transcript.txt)

# get mr.clevers hot take summary from openrouter gpt-120b-oss
echo "Generating article from Mr. Clever's perspective..."
curl https://openrouter.ai/api/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -d "{
  \"model\": \"openai/gpt-oss-120b\",
  \"messages\": [
    {
      \"role\": \"user\",
      \"content\": \"Based on the following transcript, write a compelling article from Mr. Clever's point of view on the topic he discussed. Write in his voice and style, maintaining his perspective and arguments. Make it engaging and suitable for a blog post.\\n\\nTranscript:\\n$TRANSCRIPT\"
    }
  ]
}" | jq -r '.choices[0].message.content' > article.md
echo "Article generated. Saved to article.md"

echo "Cleaning up files..."
mv clever-take-audio.mp3 last-gen/
mv transcript.txt last-gen/
mv article.md last-gen/
echo "Clean up complete."