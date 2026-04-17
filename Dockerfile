FROM python:3.11-slim

# Disable Python stdout buffering to ensure logs are printed immediately
ENV PYTHONUNBUFFERED=1

# Everything (repo, venv, playwright) lives inside /opt/data which is the
# persistent volume.  This image only provides tools; the first boot of the
# entrypoint clones and installs everything into /opt/data.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/data/playwright

# ── 1. System dependencies ──────────────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential git curl wget openssh-server ca-certificates gnupg \
        ripgrep ffmpeg gcc g++ make python3-dev libffi-dev procps && \
    rm -rf /var/lib/apt/lists/*

# ── 1b. Node.js 22 from NodeSource ──────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# ── 2. Install uv ───────────────────────────────────────────────────────────
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    ln -s /root/.local/bin/uv /usr/local/bin/uv

# ── 3. Entrypoint at /opt/entrypoint.sh ─────────────────────────────────────
#    The SDL mounts the persistent volume at /opt/data (NOT /opt), so
#    /opt/entrypoint.sh is in the image layer and always accessible.
RUN mkdir -p /opt/data
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

ENV HERMES_HOME=/opt/data

ENTRYPOINT ["/opt/entrypoint.sh"]
