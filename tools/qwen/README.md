# Qwen Code Setup

## Installation

```bash
npm install -g @qwen-code/qwen-code@latest
```

## Authentication

Qwen requires manual OAuth on first run:
```bash
qwen
# Follow the OAuth prompts
```

Note: Unlike other tools, qwen doesn't have a persistent token that can be stored in `.env`. Each machine needs manual authentication.

## Usage

```bash
qwen              # start interactive session
qwen "query"      # one-shot query
```
