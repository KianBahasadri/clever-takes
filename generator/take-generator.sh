#!/bin/bash

set -euo pipefail

# Source environment variables
source .env.generator

# Parse arguments
if [ "${1:-}" ] && [ -z "${2:-}" ]; then
    VOD_LINK="$1"
    START_TIME=""
    END_TIME=""
elif [ "${1:-}" ] && [ "${2:-}" ] && [ "${3:-}" ]; then
    START_TIME="$1"
    END_TIME="$2"
    VOD_LINK="$3"
else
    read -p "Enter VOD link: " VOD_LINK
    read -p "Enter start time (HH:MM:SS) [optional]: " START_TIME
    read -p "Enter end time (HH:MM:SS) [optional]: " END_TIME
fi

# Download audio
if [ "$START_TIME" ] && [ "$END_TIME" ]; then
    yt-dlp --extract-audio --audio-format mp3 --download-sections "*${START_TIME}-${END_TIME}" "$VOD_LINK" -o "clever-take-audio.mp3"
else
    yt-dlp --extract-audio --audio-format mp3 "$VOD_LINK" -o "clever-take-audio.mp3"
fi

# Transcribe with Whisper
./venv/bin/whisper --output_format txt clever-take-audio.mp3
mv clever-take-audio.txt transcript.txt

TRANSCRIPT=$(cat transcript.txt)

# Content generation prompt
CONTENT_PROMPT="Based on the following transcript, write a compelling article from Mr. Clever's point of view. Guidelines:
1. Voice & Style: Write casually and conversationally, like talking to friends. Keep it enthusiastic but authentic - not corporate or overly polished. Use short punchy sentences mixed with explanations.
2. Length: Aim for between 500-2000 words. Expand naturally on the key points without padding.
3. Stay Grounded: Elaborate on ideas from the transcript, but don't invent specific facts, tools, websites, or technical details that weren't mentioned. Keep vague things vague.
4. Formatting: Use simple Markdown (## headers, **bold**, *italics*, blockquotes). Avoid tables, complex layouts, or TL;DR sections.
5. Authenticity: Write like Mr. Clever sharing genuine thoughts and experiences, not marketing copy. Include personality and natural enthusiasm.
6. Structure: Start with an attention-grabbing introduction that hooks the reader. Use first-person perspective throughout.
7. Technical: Do not repeat the title in the article body. Return strictly valid JSON matching the schema.

Transcript:
"

# Generate article with OpenRouter
STRUCTURED_RESPONSE=$(jq -n \
  --arg transcript "$TRANSCRIPT" \
  --arg prompt "$CONTENT_PROMPT" \
  '{
    model: "openai/gpt-oss-120b",
    max_tokens: 2000,
    messages: [{
      role: "user",
      content: "\($prompt)\($transcript)"
    }],
    response_format: {
      type: "json_schema",
      json_schema: {
        name: "blog_post_with_body",
        strict: true,
        schema: {
          type: "object",
          properties: {
            title: { type: "string", description: "A compelling blog post title" },
            description: { type: "string", description: "Meta description, max 160 characters" },
            categories: { type: "array", items: { type: "string" }, minItems: 1, maxItems: 2, description: "1-2 categories relevant to the content" },
            tags: { type: "array", items: { type: "string" }, description: "Relevant, lowercase tags" },
            content: { type: "string", description: "Markdown article body without any title heading" }
          },
          required: ["title", "description", "categories", "tags", "content"],
          additionalProperties: false
        }
      }
    }
  }' | curl -s https://openrouter.ai/api/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -d @-)

POST_JSON=$(echo "$STRUCTURED_RESPONSE" | jq -r '.choices[0].message.content')

# Extract fields
TITLE=$(echo "$POST_JSON" | jq -r '.title')
DESCRIPTION=$(echo "$POST_JSON" | jq -r '.description')
CATEGORIES=$(echo "$POST_JSON" | jq -c '.categories')
TAGS=$(echo "$POST_JSON" | jq -c '.tags')
CONTENT_BODY=$(echo "$POST_JSON" | jq -r '.content')


# Create post file
TODAY=$(date +%Y-%m-%d)
DATE=$(date +'%Y-%m-%d %H:%M:%S %z')
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]//g' | tr ' ' '-' | sed 's/-\+/-/g')
POST_PATH="../_posts/${TODAY}-${SLUG}.md"

cat > "$POST_PATH" << EOF
---
title: "$TITLE"
date: "$DATE"
description: "$DESCRIPTION"
categories: $CATEGORIES
tags: $TAGS
---
$CONTENT_BODY
EOF

# Save to last-generated-article
mkdir -p last-generated-article
mv clever-take-audio.mp3 transcript.txt last-generated-article/
echo "$CONTENT_BODY" > last-generated-article/article.md
echo "$POST_JSON" | jq 'del(.content)' > last-generated-article/frontmatter.json

echo "Post created at $POST_PATH"
