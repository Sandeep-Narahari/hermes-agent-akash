FROM python:3.11-slim

# Disable Python stdout buffering to ensure logs are printed immediately
ENV PYTHONUNBUFFERED=1

# ── 1. System dependencies ──────────────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential git curl wget openssh-server ca-certificates gnupg \
        ripgrep ffmpeg gcc g++ make python3-dev libffi-dev procps rsync && \
    rm -rf /var/lib/apt/lists/*

# ── 1b. Node.js 22 from NodeSource ──────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# ── 2. Install uv ───────────────────────────────────────────────────────────
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    ln -s /root/.local/bin/uv /usr/local/bin/uv

# ── 3. Clone & build everything at image build time ─────────────────────────
#    Built into /app/hermes-build (image layer) so it's always available.
#    On first boot the entrypoint rsyncs this into /opt/data/hermes (PVC).
ARG HERMES_BRANCH=main
RUN git clone --branch "${HERMES_BRANCH}" \
        https://github.com/NousResearch/hermes-agent.git /app/hermes-build

WORKDIR /app/hermes-build

# ── 4. Node dependencies & Playwright ───────────────────────────────────────
ENV PLAYWRIGHT_BROWSERS_PATH=/app/hermes-build/playwright-browsers
RUN npm install --prefer-offline --no-audit && \
    npx playwright install --with-deps chromium --only-shell && \
    npm cache clean --force

# ── 5. Python virtual-env & dependencies ────────────────────────────────────
RUN uv venv && \
    uv pip install --no-cache-dir -e ".[all]"

# ── 5b. Reset git state ─────────────────────────────────────────────────────
RUN git checkout -- . && git clean -fd

# ── 6. Entrypoint at /opt/entrypoint.sh (outside /opt/data mount) ───────────
RUN mkdir -p /opt/data/hermes
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

ENV HERMES_HOME=/opt/data
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/data/hermes/playwright-browsers

# Shell lands here when user execs into the container
WORKDIR /opt/data/hermes

ENTRYPOINT ["/opt/entrypoint.sh"]
