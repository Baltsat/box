#!/bin/bash
# auto-memory: detect memorable content in user prompts via keyword matching
# injects additionalContext so claude evaluates and saves to memory if confirmed
# zero API, zero latency — pure bash regex filter

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')

# skip short/trivial
[[ ${#PROMPT} -lt 10 ]] && exit 0

# detect memorable patterns (case-insensitive)
# i (\w+ )*prefer = "i prefer", "i always prefer", "i strongly prefer" etc
if echo "$PROMPT" | grep -qiE '(always use|never use|i (\w+ )*prefer|use .+ (not|instead|over)|remember that|don.t (ever |always )?use|i (always |never )?(like|hate|want)|by default .+ use|запомни|всегда (используй|юзай)|никогда не|предпочитаю|юзай .+ (а не|вместо))'; then
    jq -n '{"additionalContext": "[AUTO-MEMORY] user message contains a preference or convention. evaluate and save to auto memory (MEMORY.md or topic file) quietly if confirmed."}'
fi

exit 0
