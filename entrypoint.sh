#!/bin/bash
# ============================================================================
# Hermes Agent – Akash/Docker Entrypoint
# Bootstraps config, env vars, migration, SSH, and skills into the data volume,
# then launches hermes in gateway or CLI mode.
# ============================================================================
set -e

export HERMES_HOME="${HERMES_HOME:-/opt/data}"
INSTALL_DIR="/opt/data/hermes"
SEED_DIR="/app/hermes-seed"

# ── Seed & fix: rsync pre-built seed into persistent volume ──────────────────
# The Akash PVC mounts at /opt/data and starts EMPTY on first deployment,
# wiping anything the image put there at build time.
# Everything was pre-built into /app/hermes-seed at Docker build time.
# We rsync it into /opt/data/hermes on first boot only (handles non-empty dirs).
# The .setup_complete marker ensures we also fix existing deployments that
# have the venv but with editable install paths pointing to /app/hermes-seed.
if [ ! -f "${INSTALL_DIR}/.setup_complete" ]; then
    echo "==> Setting up Hermes in persistent storage..."
    mkdir -p "${INSTALL_DIR}"
    rsync -a "${SEED_DIR}/" "${INSTALL_DIR}/"

    # Re-run editable install so venv paths point to /opt/data/hermes
    # (the seed venv has hardcoded paths to /app/hermes-seed)
    echo "==> Fixing Python package paths for persistent storage..."
    cd "${INSTALL_DIR}"
    source "${INSTALL_DIR}/.venv/bin/activate"
    uv pip install --no-cache-dir -e ".[all]"

    # Mark setup complete — subsequent boots skip all of the above
    touch "${INSTALL_DIR}/.setup_complete"
    echo "==> Done. Hermes is running from persistent storage."
fi

# ── Remove the seed copy — only /opt/data/hermes should exist at runtime ─────
rm -rf "${SEED_DIR}" 2>/dev/null || true

# ── Always work from the persistent copy ─────────────────────────────────────
cd "${INSTALL_DIR}"

# ── Activate the Python virtual-env ──────────────────────────────────────────
source "${INSTALL_DIR}/.venv/bin/activate"

# ── Optional: pull latest code on every boot ─────────────────────────────────
# Set AUTO_UPDATE=true to git-pull on container start.
if [ "${AUTO_UPDATE,,}" = "true" ] && [ -d "${INSTALL_DIR}/.git" ]; then
    echo "AUTO_UPDATE is enabled — pulling latest code..."
    cd "${INSTALL_DIR}"
    git fetch origin
    git reset --hard origin/"${HERMES_BRANCH:-main}"
    # Reinstall Python deps in case pyproject.toml changed
    uv pip install --no-cache-dir -e ".[all]" 2>/dev/null || true
    # Reinstall Node deps in case package.json changed
    npm install --prefer-offline --no-audit 2>/dev/null || true
    echo "Update complete."
fi

# ── Optional Bulk Migration ──────────────────────────────────────────────────
# If HERMES_HOME is uninitialized, pull in an entire older backup
# (including config.yaml, memories, sessions, etc.)
if [ ! -f "$HERMES_HOME/config.yaml" ]; then
    if [ -n "$HERMES_MIGRATION_URL" ]; then
        echo "Found HERMES_MIGRATION_URL. Downloading migration archive..."
        curl -sL "$HERMES_MIGRATION_URL" -o /tmp/migration.tar.gz || \
            wget -qO /tmp/migration.tar.gz "$HERMES_MIGRATION_URL"
        if [ -f /tmp/migration.tar.gz ]; then
            echo "Extracting archive directly into $HERMES_HOME..."
            tar -xzf /tmp/migration.tar.gz -C "$HERMES_HOME" --strip-components=1 || true
            rm -f /tmp/migration.tar.gz
        else
            echo "Warning: Failed to download migration archive from $HERMES_MIGRATION_URL"
        fi
    elif [ -n "$HERMES_MIGRATION_DIR" ] && [ -d "$HERMES_MIGRATION_DIR" ]; then
        echo "Found HERMES_MIGRATION_DIR at $HERMES_MIGRATION_DIR. Copying all files to $HERMES_HOME..."
        cp -pnR "$HERMES_MIGRATION_DIR/"* "$HERMES_HOME/" || true
    fi
fi

# ── Create essential directory structure ─────────────────────────────────────
mkdir -p "$HERMES_HOME"/{cron,sessions,logs,hooks,memories,skills,skins,plans,workspace,home}

# ── SSH server (optional) ────────────────────────────────────────────────────
if [ -n "$SSH_PASSWORD" ] || [ -n "$SSH_PUBKEY" ]; then
    mkdir -p /run/sshd
    if [ -n "$SSH_PASSWORD" ]; then
        echo "root:$SSH_PASSWORD" | chpasswd
        sed -i 's/#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
        sed -i 's/#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    fi
    if [ -n "$SSH_PUBKEY" ]; then
        mkdir -p /root/.ssh
        echo "$SSH_PUBKEY" >> /root/.ssh/authorized_keys
        chmod 700 /root/.ssh
        chmod 600 /root/.ssh/authorized_keys
        sed -i 's/#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    fi
    /usr/sbin/sshd
    echo "SSH server started."
fi

# ── .env bootstrap ──────────────────────────────────────────────────────────
if [ ! -f "$HERMES_HOME/.env" ]; then
    cp "$INSTALL_DIR/.env.example" "$HERMES_HOME/.env"

    # Auto-populate .env from Akash / Docker environment variables
    echo "Populating .env from environment variables..."
    [ -n "$TELEGRAM_BOT_TOKEN" ]     && echo "TELEGRAM_BOT_TOKEN=\"$TELEGRAM_BOT_TOKEN\""         >> "$HERMES_HOME/.env"
    [ -n "$TELEGRAM_ALLOWED_USERS" ] && echo "TELEGRAM_ALLOWED_USERS=\"$TELEGRAM_ALLOWED_USERS\"" >> "$HERMES_HOME/.env"
    [ -n "$DISCORD_BOT_TOKEN" ]      && echo "DISCORD_BOT_TOKEN=\"$DISCORD_BOT_TOKEN\""           >> "$HERMES_HOME/.env"
    [ -n "$SLACK_BOT_TOKEN" ]        && echo "SLACK_BOT_TOKEN=\"$SLACK_BOT_TOKEN\""               >> "$HERMES_HOME/.env"
    [ -n "$SLACK_APP_TOKEN" ]        && echo "SLACK_APP_TOKEN=\"$SLACK_APP_TOKEN\""               >> "$HERMES_HOME/.env"
    [ -n "$OPENAI_API_KEY" ]         && echo "OPENAI_API_KEY=\"$OPENAI_API_KEY\""                 >> "$HERMES_HOME/.env"
    [ -n "$OPENAI_BASE_URL" ]        && echo "OPENAI_BASE_URL=\"$OPENAI_BASE_URL\""               >> "$HERMES_HOME/.env"
    [ -n "$WHATSAPP_ENABLED" ]       && echo "WHATSAPP_ENABLED=\"$WHATSAPP_ENABLED\""             >> "$HERMES_HOME/.env"
    [ -n "$SIGNAL_HTTP_URL" ]        && echo "SIGNAL_HTTP_URL=\"$SIGNAL_HTTP_URL\""               >> "$HERMES_HOME/.env"
    [ -n "$MATRIX_HOMESERVER" ]      && echo "MATRIX_HOMESERVER=\"$MATRIX_HOMESERVER\""           >> "$HERMES_HOME/.env"
    [ -n "$DINGTALK_CLIENT_ID" ]     && echo "DINGTALK_CLIENT_ID=\"$DINGTALK_CLIENT_ID\""         >> "$HERMES_HOME/.env"
    [ -n "$FEISHU_APP_ID" ]          && echo "FEISHU_APP_ID=\"$FEISHU_APP_ID\""                   >> "$HERMES_HOME/.env"
    [ -n "$WECOM_BOT_ID" ]           && echo "WECOM_BOT_ID=\"$WECOM_BOT_ID\""                     >> "$HERMES_HOME/.env"
    [ -n "$TWILIO_ACCOUNT_SID" ]     && echo "TWILIO_ACCOUNT_SID=\"$TWILIO_ACCOUNT_SID\""         >> "$HERMES_HOME/.env"
    [ -n "$EMAIL_ADDRESS" ]          && echo "EMAIL_ADDRESS=\"$EMAIL_ADDRESS\""                   >> "$HERMES_HOME/.env"
fi

# ── config.yaml bootstrap ───────────────────────────────────────────────────
if [ ! -f "$HERMES_HOME/config.yaml" ]; then
    cp "$INSTALL_DIR/cli-config.yaml.example" "$HERMES_HOME/config.yaml"

    # Use Python to safely update config.yaml
    python3 - <<'PYEOF'
import yaml, os, sys

cfg_path = os.path.join(os.environ["HERMES_HOME"], "config.yaml")
with open(cfg_path, "r", encoding="utf-8") as f:
    cfg = yaml.safe_load(f) or {}

model_cfg = cfg.get("model", {})
if not isinstance(model_cfg, dict):
    model_cfg = {}

custom_model = os.getenv("LLM_MODEL", "").strip()
base_url     = os.getenv("OPENAI_BASE_URL", "").strip().rstrip("/")
api_key      = os.getenv("OPENAI_API_KEY", "").strip()

if custom_model:
    model_cfg["default"]  = custom_model
    model_cfg["provider"] = "custom"
if base_url:
    model_cfg["base_url"] = base_url
if api_key:
    model_cfg["api_key"] = api_key

cfg["model"] = model_cfg

with open(cfg_path, "w", encoding="utf-8") as f:
    yaml.dump(cfg, f, default_flow_style=False, allow_unicode=True)

if custom_model or base_url or api_key:
    print(f"Config updated: model={custom_model or '(unchanged)'}, base_url={base_url or '(unchanged)'}")
PYEOF
fi

# ── SOUL.md ──────────────────────────────────────────────────────────────────
if [ ! -f "$HERMES_HOME/SOUL.md" ]; then
    cp "$INSTALL_DIR/docker/SOUL.md" "$HERMES_HOME/SOUL.md"
fi

# ── Sync bundled skills ──────────────────────────────────────────────────────
if [ -d "$INSTALL_DIR/skills" ]; then
    python3 "$INSTALL_DIR/tools/skills_sync.py"
fi

# ── Launch ───────────────────────────────────────────────────────────────────
if [ $# -eq 0 ] && {
    [ -n "$TELEGRAM_BOT_TOKEN" ] ||
    [ -n "$DISCORD_BOT_TOKEN" ] ||
    [ -n "$SLACK_BOT_TOKEN" ] ||
    [ -n "$SLACK_APP_TOKEN" ] ||
    [ -n "$WHATSAPP_ENABLED" ] ||
    [ -n "$SIGNAL_HTTP_URL" ] ||
    [ -n "$MATRIX_HOMESERVER" ] ||
    [ -n "$DINGTALK_CLIENT_ID" ] ||
    [ -n "$FEISHU_APP_ID" ] ||
    [ -n "$WECOM_BOT_ID" ] ||
    [ -n "$TWILIO_ACCOUNT_SID" ] ||
    [ -n "$EMAIL_ADDRESS" ]; }; then
    exec hermes gateway
fi

exec hermes "$@"
