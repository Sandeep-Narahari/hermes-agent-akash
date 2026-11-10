#!/bin/bash
# ============================================================================
# hermes-agent-akash entrypoint (PID 1 is tini).
#
#  1. Install Hermes on first boot with the official installer (untouched
#     upstream code, git install on the volume). Re-runs if an install was
#     interrupted.
#  2. Optional `hermes update` on boot (AUTO_UPDATE=true).
#  3. Sync deployment env vars into $HERMES_HOME/.env / config.yaml.
#  4. Optional SSH server, web terminal (ttyd) and dashboard.
#  5. Messaging gateway in a restart loop (so `/update` from chat, which makes
#     the gateway exit with code 75 to be restarted, picks up the new code).
# ============================================================================
set -u

export HOME="${HOME:-/opt/data}"
export HERMES_HOME="${HERMES_HOME:-/opt/data/data_dir}"
export HERMES_INSTALL_DIR="${HERMES_INSTALL_DIR:-/opt/data/hermes-agent}"
export PATH="${HOME}/.local/bin:${PATH}"

INSTALLER_URLS="${HERMES_INSTALLER_URL:-https://hermes-agent.nousresearch.com/install.sh https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh}"

log() { echo "[akash] $*"; }
is_true() { case "${1:-}" in 1|true|TRUE|True|yes|YES|Yes|on|ON) return 0 ;; *) return 1 ;; esac; }

mkdir -p "$HOME" "$HERMES_HOME"
cd "$HOME"

# ── Optional bulk import of an older Hermes home into an empty volume ───────
if [ ! -f "$HERMES_HOME/config.yaml" ]; then
    if [ -n "${HERMES_MIGRATION_URL:-}" ]; then
        log "Downloading migration archive from HERMES_MIGRATION_URL..."
        if curl -fsSL --retry 3 -o /tmp/migration.tar.gz "$HERMES_MIGRATION_URL"; then
            tar -xzf /tmp/migration.tar.gz -C "$HERMES_HOME" --strip-components=1 || \
                log "Warning: failed to extract migration archive"
        else
            log "Warning: failed to download migration archive"
        fi
        rm -f /tmp/migration.tar.gz
    elif [ -n "${HERMES_MIGRATION_DIR:-}" ] && [ -d "$HERMES_MIGRATION_DIR" ]; then
        log "Copying $HERMES_MIGRATION_DIR into $HERMES_HOME..."
        cp -pnR "$HERMES_MIGRATION_DIR/." "$HERMES_HOME/" || true
    fi
fi

# ── 1. Install (first boot, or resume an interrupted install) ───────────────
installed() {
    [ -f "$HERMES_INSTALL_DIR/.hermes-bootstrap-complete" ] && command -v hermes >/dev/null 2>&1
}

if ! installed; then
    log "Installing Hermes Agent with the official installer (first boot takes a few minutes)..."
    installer=""
    for url in $INSTALLER_URLS; do
        if curl -fsSL --retry 3 -o /tmp/hermes-install.sh "$url"; then
            installer=/tmp/hermes-install.sh
            log "Fetched installer from $url"
            break
        fi
        log "Warning: could not fetch installer from $url"
    done
    if [ -z "$installer" ]; then
        log "ERROR: could not download the Hermes installer. Retrying on next restart."
        sleep 30
        exit 1
    fi
    install_args=(--non-interactive --dir "$HERMES_INSTALL_DIR")
    [ -n "${HERMES_INSTALL_CHANNEL:-}" ] && install_args+=(--channel "$HERMES_INSTALL_CHANNEL")
    if ! bash "$installer" "${install_args[@]}"; then
        log "ERROR: Hermes installer failed (see output above). Retrying on next restart."
        sleep 30
        exit 1
    fi
    rm -f "$installer"
    hash -r
    installed || { log "ERROR: install finished but 'hermes' is not available."; sleep 30; exit 1; }
    log "Hermes installed: $(hermes --version 2>/dev/null | head -1)"
elif is_true "${AUTO_UPDATE:-}"; then
    # ── 2. Optional update on boot ───────────────────────────────────────────
    log "AUTO_UPDATE enabled — running 'hermes update'..."
    hermes update || log "Warning: 'hermes update' failed — continuing with the installed version"
fi

# ── Legacy code copy left by the pre-v0.23 image ────────────────────────────
if [ -d /opt/data/hermes/.venv ]; then
    if is_true "${AKASH_PRUNE_LEGACY:-}"; then
        log "AKASH_PRUNE_LEGACY set — removing old code copy at /opt/data/hermes"
        rm -rf /opt/data/hermes /opt/data/.setup_complete_v2 /opt/data/.akash_ownership_v1
    else
        log "Notice: /opt/data/hermes is an unused code copy from the old image (~2 GB)."
        log "        Set AKASH_PRUNE_LEGACY=true once to delete it."
    fi
fi

# ── 3. Env -> .env / config.yaml ────────────────────────────────────────────
# Hermes loads .env with override=True, so a stale value would beat a changed
# SDL env var: upsert matching env vars each boot (only when they differ).
ENV_PREFIX_RE='^(TELEGRAM|DISCORD|SLACK|WHATSAPP|SIGNAL|MATRIX|DINGTALK|FEISHU|WECOM|WEIXIN|TWILIO|SMS|EMAIL|MATTERMOST|HOMEASSISTANT|GOOGLE_CHAT|BLUEBUBBLES|GATEWAY|OPENAI|OPENROUTER|ANTHROPIC)_[A-Z0-9_]*$|^[A-Z][A-Z0-9_]*_API_KEY$'

env_file_value() {
    # Current value of $1 in .env, quotes stripped ("" if absent).
    [ -f "$HERMES_HOME/.env" ] || return 0
    grep -E "^[[:space:]]*(export[[:space:]]+)?$1=" "$HERMES_HOME/.env" | tail -1 | \
        sed -E "s/^[^=]*=//; s/^\"(.*)\"\$/\\1/; s/^'(.*)'\$/\\1/"
}

synced=0
while IFS= read -r name; do
    value="${!name:-}"
    [ -n "$value" ] || continue
    [ "$(env_file_value "$name")" = "$value" ] && continue
    if hermes config set "$name" "$value" >/dev/null 2>&1; then
        synced=$((synced + 1))
    else
        log "Warning: could not write $name to .env"
    fi
done < <(compgen -e | grep -E "$ENV_PREFIX_RE" | sort)
[ "$synced" -gt 0 ] && log ".env: updated $synced key(s) from the deployment environment"

set_config() {
    hermes config set --force "$1" "$2" >/dev/null 2>&1 || \
        hermes config set "$1" "$2" >/dev/null 2>&1 || \
        log "Warning: could not set $1"
}
[ -n "${LLM_MODEL:-}" ] && set_config model.default "$LLM_MODEL"
if [ -n "${OPENAI_BASE_URL:-}" ]; then
    # Explicit OpenAI-compatible endpoint (AkashML, vLLM, ...) = custom provider.
    set_config model.provider custom
    set_config model.base_url "${OPENAI_BASE_URL%/}"
fi
[ -n "${OPENAI_API_KEY:-}" ] && set_config model.api_key "$OPENAI_API_KEY"
# Hermes defaults to "medium"; some models reject it (AkashML Kimi-K3.1-Pro
# only accepts low/high/max).
[ -n "${REASONING_EFFORT:-}" ] && set_config agent.reasoning_effort "${REASONING_EFFORT,,}"
if [ -n "${LLM_MODEL:-}${OPENAI_BASE_URL:-}${REASONING_EFFORT:-}" ]; then
    log "config.yaml: model=${LLM_MODEL:-(unchanged)} base_url=${OPENAI_BASE_URL:-(unchanged)} reasoning_effort=${REASONING_EFFORT:-(unchanged)}"
fi

# ── 4a. SSH server ──────────────────────────────────────────────────────────
if [ -n "${SSH_PASSWORD:-}" ] || [ -n "${SSH_PUBKEY:-}" ]; then
    mkdir -p /run/sshd "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    if [ -n "${SSH_PASSWORD:-}" ]; then
        echo "root:${SSH_PASSWORD}" | chpasswd
        sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    fi
    if [ -n "${SSH_PUBKEY:-}" ]; then
        touch "$HOME/.ssh/authorized_keys"
        grep -qxF "$SSH_PUBKEY" "$HOME/.ssh/authorized_keys" || echo "$SSH_PUBKEY" >> "$HOME/.ssh/authorized_keys"
        chmod 600 "$HOME/.ssh/authorized_keys"
    fi
    key_dir="$HERMES_HOME/ssh-host-keys"   # persisted: clients keep trusting the host
    mkdir -p "$key_dir" && chmod 700 "$key_dir"
    for type in rsa ecdsa ed25519; do
        key="$key_dir/ssh_host_${type}_key"
        [ -f "$key" ] || ssh-keygen -t "$type" -f "$key" -N "" -q
        chmod 600 "$key"
        grep -qxF "HostKey $key" /etc/ssh/sshd_config || echo "HostKey $key" >> /etc/ssh/sshd_config
    done
    /usr/sbin/sshd && log "SSH server started." || log "Warning: sshd failed to start"
fi

# Keep a background command alive: restart it whenever it exits.
supervise() {
    local name="$1"; shift
    (
        while true; do
            "$@"
            code=$?
            log "$name exited (code $code) — restarting in 3s"
            sleep 3
        done
    ) &
}

# ── 4b. Web terminal ────────────────────────────────────────────────────────
if is_true "${WEB_TERMINAL_ENABLED:-}"; then
    port="${WEB_TERMINAL_PORT:-7681}"
    if [ -z "${WEB_TERMINAL_PASSWORD:-}" ]; then
        WEB_TERMINAL_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)"
        echo "================================================================"
        echo "  Web terminal login: user / ${WEB_TERMINAL_PASSWORD}   (auto-generated)"
        echo "  Set WEB_TERMINAL_PASSWORD to use a fixed password."
        echo "================================================================"
    fi
    log "Starting web terminal on port $port"
    # -d 3: errors/warnings only (default notices print the credential).
    TERM=xterm-256color COLORTERM=truecolor supervise web-terminal \
        ttyd -d 3 --port "$port" --writable -t rendererType=canvas \
        --credential "user:${WEB_TERMINAL_PASSWORD}" /bin/bash -l
fi

# ── 4c. Dashboard ───────────────────────────────────────────────────────────
if is_true "${HERMES_DASHBOARD:-}"; then
    log "Starting dashboard on port ${HERMES_DASHBOARD_PORT:-9119}"
    supervise dashboard hermes dashboard \
        --host "${HERMES_DASHBOARD_HOST:-0.0.0.0}" --port "${HERMES_DASHBOARD_PORT:-9119}" --no-open
fi

# ── 5. Main process ─────────────────────────────────────────────────────────
# Explicit command (`docker run <image> chat -q hi`, `bash`, ...).
if [ $# -gt 0 ]; then
    if command -v "$1" >/dev/null 2>&1 && [ "${1#-}" = "$1" ]; then
        exec "$@"
    fi
    exec hermes "$@"
fi

if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] || [ -n "${DISCORD_BOT_TOKEN:-}" ] || \
   [ -n "${SLACK_BOT_TOKEN:-}" ] || [ -n "${SLACK_APP_TOKEN:-}" ] || \
   [ -n "${WHATSAPP_ENABLED:-}" ] || [ -n "${SIGNAL_HTTP_URL:-}" ] || \
   [ -n "${MATRIX_HOMESERVER:-}" ] || [ -n "${DINGTALK_CLIENT_ID:-}" ] || \
   [ -n "${FEISHU_APP_ID:-}" ] || [ -n "${WECOM_BOT_ID:-}" ] || \
   [ -n "${TWILIO_ACCOUNT_SID:-}" ] || [ -n "${EMAIL_ADDRESS:-}" ] || \
   is_true "${GATEWAY_FORCE:-}"; then
    log "Messaging platform configured — starting gateway."
    # Restart loop: `/update` (and `hermes gateway restart`) make the gateway
    # exit with code 75 and expect a supervisor to start the new code.
    while true; do
        hermes gateway run
        code=$?
        if [ "$code" -eq 75 ]; then
            log "Gateway requested a restart (code 75) — restarting with current code"
            sleep 1
        elif pgrep -f -- ' gateway (run|restart|start)( |$)' >/dev/null 2>&1; then
            # `hermes gateway restart` from a shell (no service manager in the
            # container) runs its own foreground gateway; ours then exits 0
            # because one gateway per host is allowed. Wait for that one to end.
            log "Another gateway is running (started from a shell) — waiting for it to exit"
            while pgrep -f -- ' gateway (run|restart|start)( |$)' >/dev/null 2>&1; do sleep 10; done
            log "That gateway exited — taking over"
        else
            log "Gateway exited (code $code) — restarting in 5s"
            sleep 5
        fi
    done
fi

log "No messaging platform configured — gateway not started."
log "Use the web terminal (WEB_TERMINAL_ENABLED=true) or SSH, then run: hermes"
exec sleep infinity
