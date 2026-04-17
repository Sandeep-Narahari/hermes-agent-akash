# hermes-agent-akash

Custom Docker image for the [Hermes AI Agent](https://github.com/NousResearch/hermes-agent), built for deployment on the [Akash Network](https://akash.network).

## Build

```bash
docker build -t hermes-agent-akash:latest .
```

## Run

```bash
docker run -d \
  -e OPENAI_BASE_URL=https://api.akashml.com/v1 \
  -e OPENAI_API_KEY=akml-XXXXXXX \
  -e TELEGRAM_BOT_TOKEN=XXXXX \
  -e LLM_MODEL=Qwen/Qwen3-235B-A22B \
  -e TELEGRAM_ALLOWED_USERS=XXX \
  -e GATEWAY_ALLOW_ALL_USERS=false \
  -v hermes-data:/opt/data \
  hermes-agent-akash:latest
```

## Environment Variables

| Variable | Description |
|---|---|
| `OPENAI_BASE_URL` | LLM API base URL (e.g. `https://api.akashml.com/v1`) |
| `OPENAI_API_KEY` | Your Akash ML API key |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token from [@BotFather](https://t.me/BotFather) |
| `LLM_MODEL` | Model to use (e.g. `Qwen/Qwen3-235B-A22B`) |
| `TELEGRAM_ALLOWED_USERS` | Comma-separated Telegram user IDs allowed to use the bot |
| `GATEWAY_ALLOW_ALL_USERS` | Set `false` to restrict to allowed users only |

## Data Volume

All config, sessions and memories are stored in `/opt/data`. Always mount a volume so data persists across restarts:

```bash
-v hermes-data:/opt/data
```
