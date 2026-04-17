# hermes-agent-akash

[![Build & Publish Docker Image](https://github.com/Sandeep-Narahari/hermes-agent-akash/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/Sandeep-Narahari/hermes-agent-akash/actions/workflows/docker-publish.yml)

> Custom Akash Network Docker image for the [Hermes AI Agent](https://github.com/NousResearch/hermes-agent).  
> The image is automatically built and published to **GitHub Container Registry (GHCR)** on every push to `main`.

---

## 🐳 Pull the Image

```bash
docker pull ghcr.io/sandeep-narahari/hermes-agent-akash:latest
```

## 🚀 Quick Start (local)

```bash
docker run -d \
  -e TELEGRAM_BOT_TOKEN="your-token" \
  -e OPENAI_API_KEY="sk-..." \
  -v hermes-data:/opt/data \
  ghcr.io/sandeep-narahari/hermes-agent-akash:latest
```

## 🔑 Environment Variables

| Variable | Required | Description |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | ✅ | Telegram bot token |
| `OPENAI_API_KEY` | ✅ | LLM API key |
| `OPENAI_BASE_URL` | ❌ | Custom LLM endpoint (e.g. Akash Chat API) |
| `LLM_MODEL` | ❌ | Override the model name |
| `TELEGRAM_ALLOWED_USERS` | ❌ | Comma-separated list of allowed Telegram user IDs |
| `AUTO_UPDATE` | ❌ | Set `true` to git-pull latest code on boot |
| `HERMES_BRANCH` | ❌ | Branch to clone/update from (default: `main`) |
| `SSH_PASSWORD` | ❌ | Enable SSH access with this password |
| `SSH_PUBKEY` | ❌ | Enable SSH access with this public key |
| `HERMES_MIGRATION_URL` | ❌ | URL to a `.tar.gz` backup to restore on first boot |

## 📦 Image Tags

| Tag | Description |
|---|---|
| `latest` | Latest build from `main` |
| `main` | Same as latest |
| `sha-<short>` | Pinned to a specific commit |
| `vX.Y.Z` | Semver release tag |

## CI/CD

GitHub Actions builds and pushes on every push to `main` using `.github/workflows/docker-publish.yml`.  
No secrets to configure — it uses the built-in `GITHUB_TOKEN` for GHCR access.
