#!/bin/bash

export OPENROUTER_API_KEY=$(cat ~/git/koreader-private/openrouter.key)
export ZHIPUAI_API_KEY=$(cat ~/git/koreader-private/zhipu.key)

# aider --model openrouter/z-ai/glm-5.1
aider --model zai/glm-5-code
