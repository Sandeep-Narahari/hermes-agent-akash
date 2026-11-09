# hermes-agent-akash

Docker image for the [Hermes AI Agent](https://github.com/NousResearch/hermes-agent), built for deployment on the [Akash Network](https://akash.network).

It is a thin layer on top of the official `nousresearch/hermes-agent` image (currently **v0.23.0**). The official image provides the sealed install at `/opt/hermes`, s6-overlay supervision, a non-root runtime user, the dashboard and Matrix E2EE support. This repo adds:

- **Env → config sync.** Deployment env vars are written into `$HERMES_HOME/.env` and `config.yaml` on every boot, so editing the SDL and redeploying takes effect.
- **Legacy volume migration.** Volumes created by the old (pre-v0.23) image of this repo are fixed once: ownership is moved to the `hermes` user and the session database schema is migrated.
- **Web terminal.** Optional ttyd, supervised by s6.
- **SSH server.** Optional.
- **Default command.** Runs the messaging gateway when a platform token is set; otherwise the container idles.

## Build

```bash
docker build -t hermes-agent-akash:latest .
# pin another upstream release:
docker build --build-arg HERMES_VERSION=v0.23.0 -t hermes-agent-akash:latest .
```

## Run

```bash
docker run -d \
  -e OPENAI_BASE_URL=https://api.akashml.com/v1 \
  -e OPENAI_API_KEY=akml-XXXXXXX \
  -e LLM_MODEL=Qwen/Qwen3-235B-A22B \
  -e TELEGRAM_BOT_TOKEN=XXXXX \
  -e TELEGRAM_ALLOWED_USERS=XXX \
  -e GATEWAY_ALLOW_ALL_USERS=false \
  -v hermes-data:/opt/data \
  hermes-agent-akash:latest
```

## Environment variables

### Model

| Variable | Description |
|---|---|
| `OPENAI_BASE_URL` | OpenAI-compatible endpoint, e.g. `https://api.akashml.com/v1`. Setting it selects `provider: custom`. |
| `OPENAI_API_KEY` | API key for that endpoint (e.g. your AkashML key). |
| `LLM_MODEL` | Model name, e.g. `Qwen/Qwen3-235B-A22B`. |

### Messaging

The gateway starts when any of these is set: `TELEGRAM_BOT_TOKEN`, `DISCORD_BOT_TOKEN`, `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN`, `WHATSAPP_ENABLED`, `SIGNAL_HTTP_URL`, `MATRIX_HOMESERVER`, `DINGTALK_CLIENT_ID`, `FEISHU_APP_ID`, `WECOM_BOT_ID`, `TWILIO_ACCOUNT_SID`, `EMAIL_ADDRESS`. Set `GATEWAY_FORCE=true` to start it anyway.

These env vars are copied into `$HERMES_HOME/.env` on every boot:

- names starting with `TELEGRAM_`, `DISCORD_`, `SLACK_`, `WHATSAPP_`, `SIGNAL_`, `MATRIX_`, `DINGTALK_`, `FEISHU_`, `WECOM_`, `WEIXIN_`, `TWILIO_`, `SMS_`, `EMAIL_`, `MATTERMOST_`, `HOMEASSISTANT_`, `GOOGLE_CHAT_`, `BLUEBUBBLES_`, `GATEWAY_`, `OPENAI_`, `OPENROUTER_` or `ANTHROPIC_`;
- any name ending in `_API_KEY`.

Examples: `TELEGRAM_ALLOWED_USERS`, `MATRIX_ACCESS_TOKEN`, `MATRIX_USER_ID`, `MATRIX_ENCRYPTION`.

Removing a variable from the SDL does **not** delete it from `.env`. Edit `.env` from the terminal to remove it.

The gateway state persists across restarts. If it was running before, it comes back even when the token env vars are removed. Run `hermes gateway stop` from the terminal to stop it for good.

### Access

| Variable | Description |
|---|---|
| `WEB_TERMINAL_ENABLED` | `true` serves a bash terminal in the browser on port 7681 (ttyd). |
| `WEB_TERMINAL_PASSWORD` | Basic-auth password for user `user`. If unset, a random password is printed in the logs. |
| `WEB_TERMINAL_PORT` | Defaults to `7681`. |
| `WEB_TERMINAL_USER` | Defaults to `hermes`, the runtime user. Set `root` for a root shell; `hermes` commands still run as the `hermes` user. |
| `SSH_PASSWORD` / `SSH_PUBKEY` | Start sshd on port 22 with root login. Host keys persist on the volume. |
| `HERMES_DASHBOARD` | `true` starts the upstream web dashboard on port 9119. It requires `HERMES_DASHBOARD_BASIC_AUTH_USERNAME` and `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD`. |

### Maintenance

| Variable | Description |
|---|---|
| `HERMES_MIGRATION_URL` / `HERMES_MIGRATION_DIR` | Import an older Hermes home (`.tar.gz` URL or directory) into an empty volume on first boot. |
| `AKASH_PRUNE_LEGACY` | `true` deletes the unused `/opt/data/hermes` code copy (~2 GB) left behind by the old image. |

## Data volume

Mount a persistent volume at `/opt/data`. User data (config, `.env`, sessions, memories, skills) lives in `/opt/data/data_dir`, which is `$HERMES_HOME`. The Hermes code itself is not on the volume; it is part of the image.

## Updating Hermes

The install inside the image is read-only, so `hermes update` and the old `AUTO_UPDATE` flag no longer apply. To update:

1. Bump `HERMES_VERSION` in the `Dockerfile` to a release tag from [Docker Hub](https://hub.docker.com/r/nousresearch/hermes-agent/tags), e.g. `v0.23.0`.
2. Push to `main`. CI builds and publishes `ghcr.io/sandeep-narahari/hermes-agent-akash`.
3. Redeploy on Akash. The data volume is kept and migrated on boot.

## Upgrading from the old image (pre-v0.23)

No action is needed. On first boot the new image:

- moves ownership of `/opt/data/data_dir` to the `hermes` user (UID 10000);
- migrates the session database;
- keeps all sessions, memories and skills.

Differences from the old image:

- The web terminal shell runs as the `hermes` user, not root. Set `WEB_TERMINAL_USER=root` to get a root shell.
- `apt-get install` inside the container does not survive a restart.
- `AUTO_UPDATE` and `HERMES_BRANCH` were removed. See [Updating Hermes](#updating-hermes).
