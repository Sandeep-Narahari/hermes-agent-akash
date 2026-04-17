FROM python:3.11-slim

# Disable Python stdout buffering to ensure logs are printed immediately
ENV PYTHONUNBUFFERED=1

# Playwright browsers live under /opt/data so they persist on the volume.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/data/playwright

# ── 1. System dependencies ──────────────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential git curl wget openssh-server ca-certificates gnupg \
        ripgrep ffmpeg gcc g++ make python3-dev libffi-dev procps && \
    rm -rf /var/lib/apt/lists/*

# ── 1b. Node.js 22 from NodeSource (Debian apt only has v20) ────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# ── 2. Install uv (fast Python package manager) ─────────────────────────────
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    ln -s /root/.local/bin/uv /usr/local/bin/uv

# ── 3. Clone the full repo (preserves .git so /update works) ────────────────
#    Lives inside /opt/data which is the persistent volume mount point.
#    All code, deps, and /update pulls will survive container restarts.
ARG HERMES_BRANCH=main
RUN git clone --branch "${HERMES_BRANCH}" \
        https://github.com/NousResearch/hermes-agent.git /opt/data/hermes

WORKDIR /opt/data/hermes

# ── 4. Node dependencies & Playwright ───────────────────────────────────────
RUN npm install --prefer-offline --no-audit && \
    npx playwright install --with-deps chromium --only-shell && \
    npm cache clean --force

# ── 5. Python virtual-env & dependencies ────────────────────────────────────
RUN uv venv && \
    uv pip install --no-cache-dir -e ".[all]"

# ── 5b. Reset git state so /update sees a clean repo ────────────────────────
RUN git checkout -- . && git clean -fd

# ── 6. Entrypoint lives at /opt/entrypoint.sh ───────────────────────────────
#    The SDL mounts the persistent volume at /opt/data (NOT /opt), so
#    /opt/entrypoint.sh is safely in the image layer and always accessible.
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

ENV HERMES_HOME=/opt/data

ENTRYPOINT ["/opt/entrypoint.sh"]
