#!/bin/bash

# export OPENROUTER_API_KEY=$(cat ~/git/koreader-private/openrouter.key)
# export ZAI_API_KEY=$(cat ~/git/koreader-private/zhipu.key)
export CLOUDFLARE_ACCOUNT_ID=$(cat ~/git/koreader-private/cloudflare.id)
export OPENAI_API_KEY=$(cat ~/git/koreader-private/cloudflare.key)
export OPENAI_API_BASE="https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/ai/v1/"

# aider --model openrouter/z-ai/glm-5.1
# aider --model zai/glm-5-code
aider --model openai/@cf/zai-org/glm-5.2
