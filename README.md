# hermes-agent-akash

Docker image for running the [Hermes AI Agent](https://github.com/NousResearch/hermes-agent) on the [Akash Network](https://akash.network).

The image does **not** contain Hermes. It only provides the system libraries plus tini, ttyd and sshd. On first boot it runs the official Hermes installer (`https://hermes-agent.nousresearch.com/install.sh`), which clones the untouched upstream code onto the persistent volume. Because this is a normal git install:

- `/update` in chat and `hermes update` in the terminal update Hermes in place;
- updates survive restarts;
- the image only needs rebuilding when system packages change.

## Build

```bash
docker build -t hermes-agent-akash:latest .
```

## Run

```bash
docker run -d \
  -e OPENAI_BASE_URL=https://api.akashml.com/v1 \
  -e OPENAI_API_KEY=akml-XXXXXXX \
  -e LLM_MODEL=moonshotai/Kimi-K3.1-Pro \
  -e REASONING_EFFORT=high \
  -e TELEGRAM_BOT_TOKEN=XXXXX \
  -e TELEGRAM_ALLOWED_USERS=XXX \
  -v hermes-data:/opt/data \
  hermes-agent-akash:latest
```

The first boot takes about 4 minutes while Hermes installs. Later boots start in seconds.

## Updating Hermes

| How | What happens |
|---|---|
| `/update` in Telegram/Discord/… | Hermes pulls the latest release, then the gateway restarts on the new code. |
| `hermes update` in the web terminal or over SSH | Same, from a shell. |
| `AUTO_UPDATE=true` | Runs `hermes update` on every container start. |

By default this follows the **stable** channel (published releases). Set `HERMES_INSTALL_CHANNEL=main` before the first boot to follow every commit instead.

## Environment variables

### Model

| Variable | Description |
|---|---|
| `OPENAI_BASE_URL` | OpenAI-compatible endpoint, e.g. `https://api.akashml.com/v1`. Setting it selects `provider: custom`. |
| `OPENAI_API_KEY` | API key for that endpoint, e.g. your AkashML key. |
| `LLM_MODEL` | Model name, e.g. `moonshotai/Kimi-K3.1-Pro`. |
| `REASONING_EFFORT` | Sets `agent.reasoning_effort`. Hermes defaults to `medium`, which some models reject. AkashML's `moonshotai/Kimi-K3.1-Pro` only accepts `low`, `high` or `max`, and returns HTTP 500 otherwise. |

### Messaging

The gateway starts when any of these is set: `TELEGRAM_BOT_TOKEN`, `DISCORD_BOT_TOKEN`, `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN`, `WHATSAPP_ENABLED`, `SIGNAL_HTTP_URL`, `MATRIX_HOMESERVER`, `DINGTALK_CLIENT_ID`, `FEISHU_APP_ID`, `WECOM_BOT_ID`, `TWILIO_ACCOUNT_SID` or `EMAIL_ADDRESS`. Set `GATEWAY_FORCE=true` to start it anyway. The gateway is restarted automatically if it exits.

Env vars are copied into `$HERMES_HOME/.env` on every boot when their name:

- starts with `TELEGRAM_`, `DISCORD_`, `SLACK_`, `WHATSAPP_`, `SIGNAL_`, `MATRIX_`, `DINGTALK_`, `FEISHU_`, `WECOM_`, `WEIXIN_`, `TWILIO_`, `SMS_`, `EMAIL_`, `MATTERMOST_`, `HOMEASSISTANT_`, `GOOGLE_CHAT_`, `BLUEBUBBLES_`, `GATEWAY_`, `OPENAI_`, `OPENROUTER_` or `ANTHROPIC_`; or
- ends in `_API_KEY`.

Examples: `TELEGRAM_ALLOWED_USERS`, `MATRIX_ACCESS_TOKEN`. Removing a variable from the SDL does not delete it from `.env`. Edit `.env` from the terminal to remove it.

### Access

| Variable | Description |
|---|---|
| `WEB_TERMINAL_ENABLED` | `true` serves a root bash terminal in the browser on port 7681 (ttyd). |
| `WEB_TERMINAL_PASSWORD` | Basic-auth password for user `user`. If unset, a random one is printed in the logs. |
| `WEB_TERMINAL_PORT` | Defaults to `7681`. |
| `SSH_PASSWORD` / `SSH_PUBKEY` | Start sshd on port 22 with root login. Host keys and `authorized_keys` persist on the volume. |
| `HERMES_DASHBOARD` | `true` starts the Hermes web dashboard on port 9119. It requires `HERMES_DASHBOARD_BASIC_AUTH_USERNAME` and `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD`. |

### Maintenance

| Variable | Description |
|---|---|
| `AUTO_UPDATE` | `true` runs `hermes update` on each start. |
| `HERMES_INSTALL_CHANNEL` | `stable` (default) or `main`. Only used for the first install. |
| `HERMES_MIGRATION_URL` / `HERMES_MIGRATION_DIR` | Import an older Hermes home (`.tar.gz` URL or directory) into an empty volume on first boot. |
| `AKASH_PRUNE_LEGACY` | `true` deletes `/opt/data/hermes`, the ~2 GB code copy left by the pre-v0.23 image. |

## Data volume

Mount a persistent volume at `/opt/data`. Allow about 5 GB.

| Path | Contents |
|---|---|
| `/opt/data/hermes-agent` | Hermes git checkout, managed by the installer and `hermes update` |
| `/opt/data/data_dir` | `$HERMES_HOME`: config, `.env`, sessions, memories, skills, tools |
| `/opt/data` | `$HOME`, holding the `~/.local/bin/hermes` launcher |

## Upgrading existing deployments

Volumes from earlier versions of this image keep all their data. On the first boot with this image, Hermes is installed into `/opt/data/hermes-agent` next to the existing `data_dir`. Sessions, memories, skills and `.env` are kept, and the session database is migrated when the gateway or CLI first opens it. Volumes from the pre-v0.23 image also hold an unused `/opt/data/hermes` copy; set `AKASH_PRUNE_LEGACY=true` once to delete it.
