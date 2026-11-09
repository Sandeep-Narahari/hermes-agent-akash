"""Sync Akash deployment env vars into $HERMES_HOME/.env and config.yaml.

Runs on every boot as the hermes user (see cont-init.d/03-akash-config).

Hermes loads $HERMES_HOME/.env with override=True, so a stale value written
on an earlier boot would silently win over a changed SDL env var. We therefore
upsert every relevant env var into .env each boot. Keys not set in the
container environment are left untouched, so values configured from inside
the container (hermes setup, /sethome, ...) survive.
"""

from __future__ import annotations

import os
import re
import sys
import tempfile
from pathlib import Path

HERMES_HOME = Path(os.environ.get("HERMES_HOME", "/opt/data/data_dir"))
ENV_PATH = HERMES_HOME / ".env"
CONFIG_PATH = HERMES_HOME / "config.yaml"

# Env vars forwarded into .env: any name with one of these prefixes, plus
# any *_API_KEY. Container-plumbing vars (HERMES_*, SSH_*, WEB_TERMINAL_*,
# S6_*, PATH, ...) never match.
ENV_PREFIXES = (
    "TELEGRAM_", "DISCORD_", "SLACK_", "WHATSAPP_", "SIGNAL_", "MATRIX_",
    "DINGTALK_", "FEISHU_", "WECOM_", "WEIXIN_", "TWILIO_", "SMS_", "EMAIL_",
    "MATTERMOST_", "HOMEASSISTANT_", "GOOGLE_CHAT_", "BLUEBUBBLES_",
    "GATEWAY_", "OPENAI_", "OPENROUTER_", "ANTHROPIC_",
)
ENV_SUFFIXES = ("_API_KEY",)
_KEY_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")


def log(msg: str) -> None:
    print(f"[akash] {msg}", flush=True)


def _quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _atomic_write(path: Path, text: str, mode: int) -> None:
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def wanted_env() -> dict[str, str]:
    out = {}
    for key, value in os.environ.items():
        if not _KEY_RE.match(key) or not value.strip():
            continue
        if key.startswith(ENV_PREFIXES) or key.endswith(ENV_SUFFIXES):
            out[key] = value.strip()
    return out


def sync_env(values: dict[str, str]) -> None:
    if not values:
        return
    lines = ENV_PATH.read_text(encoding="utf-8").splitlines() if ENV_PATH.exists() else []
    remaining = dict(values)
    changed = False
    out: list[str] = []
    for line in lines:
        m = re.match(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=", line)
        key = m.group(1) if m else None
        if key in values:
            if key not in remaining:
                changed = True  # drop duplicate assignment
                continue
            new = f"{key}={_quote(remaining.pop(key))}"
            changed |= new != line
            out.append(new)
        else:
            out.append(line)
    if remaining:
        changed = True
        out.append("")
        out.append("# ── Synced from Akash deployment environment ──")
        out.extend(f"{k}={_quote(v)}" for k, v in sorted(remaining.items()))
    if changed:
        _atomic_write(ENV_PATH, "\n".join(out) + "\n", 0o600)
        log(f".env synced ({len(values)} keys from environment)")


def sync_config() -> None:
    model = os.environ.get("LLM_MODEL", "").strip()
    base_url = os.environ.get("OPENAI_BASE_URL", "").strip().rstrip("/")
    api_key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not (model or base_url or api_key) or not CONFIG_PATH.exists():
        return

    from ruamel.yaml import YAML  # round-trip mode keeps comments

    yaml = YAML()
    yaml.preserve_quotes = True
    with CONFIG_PATH.open(encoding="utf-8") as fh:
        cfg = yaml.load(fh) or {}

    model_cfg = cfg.get("model")
    if not isinstance(model_cfg, dict):
        model_cfg = {}
        cfg["model"] = model_cfg

    desired = {}
    if model:
        desired["default"] = model
    if base_url:
        # Any explicit OpenAI-compatible endpoint (AkashML, vLLM, ...) is a
        # "custom" provider; the seeded default is auto + OpenRouter.
        desired["provider"] = "custom"
        desired["base_url"] = base_url
    if api_key:
        desired["api_key"] = api_key

    changed = False
    for key, value in desired.items():
        if model_cfg.get(key) != value:
            model_cfg[key] = value
            changed = True
    if not changed:
        return

    from io import StringIO

    buf = StringIO()
    yaml.dump(cfg, buf)
    _atomic_write(CONFIG_PATH, buf.getvalue(), 0o640)
    log(
        "config.yaml updated: "
        f"model={model or '(unchanged)'} base_url={base_url or '(unchanged)'}"
    )


def main() -> int:
    if not HERMES_HOME.is_dir():
        log(f"{HERMES_HOME} missing — skipping config sync")
        return 0
    sync_env(wanted_env())
    sync_config()
    return 0


if __name__ == "__main__":
    sys.exit(main())
