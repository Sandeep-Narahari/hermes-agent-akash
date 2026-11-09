#!/bin/sh
# shellcheck shell=sh
# Default container command (runs as the hermes user via upstream's
# main-wrapper.sh). Starts the messaging gateway in the foreground when any
# platform is configured; otherwise idles so the web terminal / dashboard /
# SSH services stay up. Pass a command to `docker run` to override.
set -e

if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] || [ -n "${DISCORD_BOT_TOKEN:-}" ] || \
   [ -n "${SLACK_BOT_TOKEN:-}" ] || [ -n "${SLACK_APP_TOKEN:-}" ] || \
   [ -n "${WHATSAPP_ENABLED:-}" ] || [ -n "${SIGNAL_HTTP_URL:-}" ] || \
   [ -n "${MATRIX_HOMESERVER:-}" ] || [ -n "${DINGTALK_CLIENT_ID:-}" ] || \
   [ -n "${FEISHU_APP_ID:-}" ] || [ -n "${WECOM_BOT_ID:-}" ] || \
   [ -n "${TWILIO_ACCOUNT_SID:-}" ] || [ -n "${EMAIL_ADDRESS:-}" ] || \
   [ -n "${GATEWAY_FORCE:-}" ]; then
    echo "[akash] Messaging platform configured — starting gateway."
    cd "${HERMES_HOME:-/opt/data/data_dir}"
    exec hermes gateway run
fi

echo "[akash] No messaging env vars set — not starting a gateway from env."
echo "[akash] (A gateway that was running before a restart is restored automatically;"
echo "[akash]  stop it with: hermes gateway stop)"
exec sleep infinity
