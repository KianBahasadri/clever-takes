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
if [ -n "${1:-}" ] && [ -z "${2:-}" ]; then
    # Only link provided, process entire video
    VOD_LINK="$1"
    START_TIME=""
    END_TIME=""
    echo "Processing entire video"
elif [ -n "${1:-}" ] && [ -n "${2:-}" ] && [ -n "${3:-}" ]; then
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

# Generate title and front-matter from transcript using structured outputs
echo "Generating front-matter and title..."
FRONTMATTER_RESPONSE=$(curl -s https://openrouter.ai/api/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -d "{
  \"model\": \"openai/gpt-4o\",
  \"messages\": [
    {
      \"role\": \"user\",
      \"content\": \"Based on the following transcript, generate metadata for a blog post.\\n\\nTranscript:\\n$TRANSCRIPT\"
    }
  ],
  \"response_format\": {
    \"type\": \"json_schema\",
    \"json_schema\": {
      \"name\": \"blog_post_metadata\",
      \"strict\": true,
      \"schema\": {
        \"type\": \"object\",
        \"properties\": {
          \"title\": {
            \"type\": \"string\",
            \"description\": \"A compelling blog post title\"
          },
          \"description\": {
            \"type\": \"string\",
            \"description\": \"A short summary suitable for meta description (max 160 characters)\"
          },
          \"categories\": {
            \"type\": \"array\",
            \"items\": {
              \"type\": \"string\"
            },
            \"minItems\": 1,
            \"maxItems\": 2,
            \"description\": \"1-2 categories relevant to the content\"
          },
          \"tags\": {
            \"type\": \"array\",
            \"items\": {
              \"type\": \"string\"
            },
            \"description\": \"Array of relevant tags in lowercase\"
          }
        },
        \"required\": [\"title\", \"description\", \"categories\", \"tags\"],
        \"additionalProperties\": false
      }
    }
  }
}")

# Extract the JSON from the response - with structured outputs, content is already JSON
FRONTMATTER_JSON=$(echo "$FRONTMATTER_RESPONSE" | jq -r '.choices[0].message.content')
echo "Front-matter JSON: $FRONTMATTER_JSON"

# Extract individual fields
TITLE=$(echo "$FRONTMATTER_JSON" | jq -r '.title')
DESCRIPTION=$(echo "$FRONTMATTER_JSON" | jq -r '.description')
CATEGORIES=$(echo "$FRONTMATTER_JSON" | jq -r '.categories | @json')
TAGS=$(echo "$FRONTMATTER_JSON" | jq -r '.tags | @json')

# Generate filename with today's date
TODAY=$(date +%Y-%m-%d)
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]//g' | tr ' ' '-' | sed 's/-\+/-/g')
FILENAME="${TODAY}-${SLUG}.md"
POST_PATH="../_posts/$FILENAME"

# Generate date in the format: 2019-08-08 11:33:00 +0800
DATE=$(date +'%Y-%m-%d %H:%M:%S %z')

# Create front-matter string
FRONT_MATTER="---
title: \"$TITLE\"
date: \"$DATE\"
description: \"$DESCRIPTION\"
categories: $CATEGORIES
tags: $TAGS
---
"

# Create the full post content
FULL_POST="${FRONT_MATTER}$(cat article.md)"

# Write to the post file
echo "$FULL_POST" > "$POST_PATH"
echo "Post created at $POST_PATH"

# Also save to last-generated-article for reference
echo "$FRONTMATTER_JSON" > frontmatter.json

echo "Cleaning up files..."
mv clever-take-audio.mp3 last-generated-article/
mv transcript.txt last-generated-article/
mv article.md last-generated-article/
mv frontmatter.json last-generated-article/
echo "Clean up complete."