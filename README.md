# hermes-agent-akash

[![Build & Publish Docker Image](https://github.com/Sandeep-Narahari/hermes-agent-akash/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/Sandeep-Narahari/hermes-agent-akash/actions/workflows/docker-publish.yml)

A production-ready Docker packaging of the [Hermes AI Agent](https://github.com/NousResearch/hermes-agent) by NousResearch, purpose-built for deployment on the [Akash Network](https://akash.network). This repo contains the `Dockerfile`, `entrypoint.sh`, and a GitHub Actions CI/CD pipeline that automatically builds and publishes the image to GitHub Container Registry (GHCR) on every push to `main`.

---

## What's Inside

| File | Purpose |
|---|---|
| `Dockerfile` | Multi-stage build: installs system deps, Node 22, Python (via `uv`), clones `hermes-agent`, installs all dependencies |
| `entrypoint.sh` | Bootstrap script: seeds config, injects env vars, optionally auto-updates, starts SSH, then launches the gateway |
| `.github/workflows/docker-publish.yml` | GitHub Actions CI/CD — builds and pushes to GHCR on every `main` push or version tag |

---

## Pull the Image

```bash
docker pull ghcr.io/sandeep-narahari/hermes-agent-akash:latest
```

---

## Quick Start

```bash
docker run -d \
  --name hermes \
  -e TELEGRAM_BOT_TOKEN="your-bot-token" \
  -e OPENAI_API_KEY="sk-..." \
  -v hermes-data:/opt/data \
  ghcr.io/sandeep-narahari/hermes-agent-akash:latest
```

The container auto-detects which messaging platform tokens are set and starts the gateway accordingly. If no platform token is set, it falls back to the interactive CLI.

---

## Environment Variables

### Required (at least one messaging platform)

| Variable | Description |
|---|---|
| `TELEGRAM_BOT_TOKEN` | Telegram bot token from [@BotFather](https://t.me/BotFather) |
| `DISCORD_BOT_TOKEN` | Discord bot token |
| `SLACK_BOT_TOKEN` | Slack bot token |
| `SLACK_APP_TOKEN` | Slack app-level token (for socket mode) |
| `WHATSAPP_ENABLED` | Set to `true` to enable WhatsApp bridge |
| `SIGNAL_HTTP_URL` | Signal REST API URL |
| `MATRIX_HOMESERVER` | Matrix homeserver URL |
| `DINGTALK_CLIENT_ID` | DingTalk client ID |
| `FEISHU_APP_ID` | Feishu/Lark app ID |
| `WECOM_BOT_ID` | WeCom bot ID |
| `TWILIO_ACCOUNT_SID` | Twilio account SID (for SMS) |
| `EMAIL_ADDRESS` | Email address for the email gateway |

### LLM / Model

| Variable | Description |
|---|---|
| `OPENAI_API_KEY` | API key for your LLM provider |
| `OPENAI_BASE_URL` | Base URL for a custom LLM endpoint (e.g. Akash Chat API, Ollama) |
| `LLM_MODEL` | Override the default model name (e.g. `meta-llama/Llama-3-70b-chat-hf`) |

### Access Control

| Variable | Description |
|---|---|
| `TELEGRAM_ALLOWED_USERS` | Comma-separated Telegram user IDs that are allowed to interact with the bot |

### Maintenance & Updates

| Variable | Default | Description |
|---|---|---|
| `AUTO_UPDATE` | `false` | Set to `true` to `git pull` the latest Hermes code on every container start |
| `HERMES_BRANCH` | `main` | The Hermes upstream branch to clone and/or update from |

### SSH Access (optional)

| Variable | Description |
|---|---|
| `SSH_PASSWORD` | Set a root password to enable SSH with password auth |
| `SSH_PUBKEY` | Set a public key to enable SSH with key-based auth |

SSH listens on port `22`. Map it when running locally with `-p 2222:22`.

### Migration (first-boot restore)

| Variable | Description |
|---|---|
| `HERMES_MIGRATION_URL` | URL to a `.tar.gz` backup archive — extracted into `/opt/data` on first boot if no `config.yaml` exists |
| `HERMES_MIGRATION_DIR` | Path to a local backup directory — copied into `/opt/data` on first boot if no `config.yaml` exists |

---

## Persistent Data Volume

All user data (config, sessions, memories, logs, skills) lives in `/opt/data`. Always mount a named volume so data survives container restarts and upgrades:

```bash
-v hermes-data:/opt/data
```

### Directory layout inside `/opt/data`

```
/opt/data/
├── config.yaml        # Main Hermes config (auto-seeded from example on first boot)
├── .env               # Environment / secrets file (auto-seeded on first boot)
├── SOUL.md            # Agent personality / system prompt
├── sessions/          # Conversation sessions
├── memories/          # Long-term memories
├── skills/            # Custom skills
├── logs/              # Runtime logs
├── workspace/         # Agent working directory
└── home/              # Agent home directory
```

---

## Image Tags

| Tag | When it's published |
|---|---|
| `latest` | Every push to `main` |
| `main` | Every push to `main` |
| `sha-<short>` | Every build (pinned to a specific commit) |
| `vX.Y.Z` | When a Git tag like `v1.2.0` is pushed |
| `X.Y` | Same semver tag push (major.minor only) |

---

## CI/CD

GitHub Actions workflow at `.github/workflows/docker-publish.yml` handles everything automatically:

- **Triggers:** push to `main`, version tags (`v*.*.*`), PRs against `main` (build-only, no push), manual dispatch
- **Registry:** `ghcr.io` (GitHub Container Registry)
- **Auth:** uses the built-in `GITHUB_TOKEN` — no secrets to configure
- **Cache:** GitHub Actions layer cache (`type=gha`) for fast repeat builds
- **Concurrency:** cancels in-progress runs on the same branch to avoid wasted minutes

To publish a versioned release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

This triggers a build and pushes `v1.0.0`, `1.0`, `sha-<short>`, and `latest` to GHCR.

---

## Building Locally

```bash
docker build \
  --build-arg HERMES_BRANCH=main \
  -t hermes-agent-akash:local \
  .
```

---

## Deploying on Akash Network

Use the image in your Akash SDL:

```yaml
services:
  hermes:
    image: ghcr.io/sandeep-narahari/hermes-agent-akash:latest
    env:
      - TELEGRAM_BOT_TOKEN=<your-token>
      - OPENAI_API_KEY=<your-key>
      - OPENAI_BASE_URL=https://chatapi.akash.network/api/v1
      - LLM_MODEL=meta-llama/Llama-3-3-70B-Instruct
    expose:
      - port: 8080
        as: 80
        to:
          - global: true
```

---

## Upstream Project

This repo packages the upstream [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent). Configuration, skills, and SOUL.md documentation can be found there.
