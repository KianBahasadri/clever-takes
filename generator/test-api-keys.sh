#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Source environment variables
if [ -f ".env.generator" ]; then
    source .env.generator
else
    echo -e "${RED}Error: .env.generator file not found${NC}"
    exit 1
fi

echo "================================"
echo "API Key Test Suite"
echo "================================"
echo ""

# Test ElevenLabs API Key
echo -e "${YELLOW}Testing ElevenLabs API Key...${NC}"
if [ -z "${ELEVENLABS_API_KEY:-}" ]; then
    echo -e "${RED}✗ ELEVENLABS_API_KEY not set${NC}"
else
    ELEVENLABS_RESPONSE=$(curl -s -X GET https://api.elevenlabs.io/v1/user \
        -H "xi-api-key: ${ELEVENLABS_API_KEY}")
    
    if echo "$ELEVENLABS_RESPONSE" | jq -e '.subscription_data' > /dev/null 2>&1; then
        USER_ID=$(echo "$ELEVENLABS_RESPONSE" | jq -r '.xi_user_id')
        SUBSCRIPTION=$(echo "$ELEVENLABS_RESPONSE" | jq -r '.subscription_data.tier')
        echo -e "${GREEN}✓ ElevenLabs API Key Valid${NC}"
        echo "  User ID: $USER_ID"
        echo "  Subscription: $SUBSCRIPTION"
    else
        echo -e "${RED}✗ ElevenLabs API Key Invalid${NC}"
        echo "  Response: $(echo "$ELEVENLABS_RESPONSE" | jq '.')"
    fi
fi
echo ""

# Test OpenRouter API Key
echo -e "${YELLOW}Testing OpenRouter API Key...${NC}"
if [ -z "${OPENROUTER_API_KEY:-}" ]; then
    echo -e "${RED}✗ OPENROUTER_API_KEY not set${NC}"
else
    OPENROUTER_RESPONSE=$(curl -s https://openrouter.ai/api/v1/auth/key \
        -H "Authorization: Bearer $OPENROUTER_API_KEY")
    
    if echo "$OPENROUTER_RESPONSE" | jq -e '.data' > /dev/null 2>&1; then
        DATA=$(echo "$OPENROUTER_RESPONSE" | jq '.data')
        LIMIT=$(echo "$DATA" | jq -r '.limit')
        USAGE=$(echo "$DATA" | jq -r '.usage')
        echo -e "${GREEN}✓ OpenRouter API Key Valid${NC}"
        echo "  Limit: $LIMIT"
        echo "  Usage: $USAGE"
    else
        echo -e "${RED}✗ OpenRouter API Key Invalid${NC}"
        echo "  Response: $(echo "$OPENROUTER_RESPONSE" | jq '.')"
    fi
fi
echo ""

# Test OpenRouter Model Availability
echo -e "${YELLOW}Testing OpenRouter Model Availability (openai/gpt-oss-120b)...${NC}"
if [ -z "${OPENROUTER_API_KEY:-}" ]; then
    echo -e "${RED}✗ Cannot test - OPENROUTER_API_KEY not set${NC}"
else
    MODEL_TEST_RESPONSE=$(curl -s https://openrouter.ai/api/v1/chat/completions \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENROUTER_API_KEY" \
        -d '{
            "model": "openai/gpt-oss-120b",
            "messages": [{"role": "user", "content": "Hello"}],
            "max_tokens": 10
        }')
    
    if echo "$MODEL_TEST_RESPONSE" | jq -e '.choices[0].message.content' > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Model openai/gpt-oss-120b is available${NC}"
        CONTENT=$(echo "$MODEL_TEST_RESPONSE" | jq -r '.choices[0].message.content')
        echo "  Sample response: ${CONTENT:0:50}..."
    else
        if echo "$MODEL_TEST_RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
            ERROR_MSG=$(echo "$MODEL_TEST_RESPONSE" | jq -r '.error.message')
            echo -e "${RED}✗ Model error: $ERROR_MSG${NC}"
            echo "  Full response: $(echo "$MODEL_TEST_RESPONSE" | jq '.')"
        else
            echo -e "${RED}✗ Unexpected response from model test${NC}"
            echo "  Response: $(echo "$MODEL_TEST_RESPONSE" | jq '.')"
        fi
    fi
fi
echo ""

echo "================================"
echo "Test Complete"
echo "================================"
