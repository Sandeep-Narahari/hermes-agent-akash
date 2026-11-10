# ============================================================================
# hermes-agent-akash
#
# Runtime-only image: system libraries + tini + ttyd + sshd. Hermes itself is
# NOT baked in. On first boot the entrypoint runs the official, untouched
# Hermes installer (https://hermes-agent.nousresearch.com/install.sh), which
# clones NousResearch/hermes-agent onto the persistent volume as a git
# install. Because of that, `hermes update` / `/update` from chat work, and
# updates survive restarts. Rebuild this image only to change system packages.
# ============================================================================
FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

# Base tools + build toolchain (native Python extensions, e.g. python-olm for
# Matrix E2EE) + shared libs the pm-staged Chromium / cua-driver link against
# (same list as upstream's Dockerfile, plus libx11-6).
RUN apt-get -o Acquire::Retries=3 update && \
    apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
        ca-certificates curl wget git xz-utils procps tini tmux openssh-server \
        iputils-ping less nano rsync \
        build-essential cmake libffi-dev libolm-dev libatomic1 \
        libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 libatspi2.0-0t64 \
        libcairo2 libcups2t64 libdbus-1-3 libgbm1 libglib2.0-0t64 libnspr4 \
        libnss3 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 libxdamage1 \
        libxext6 libxfixes3 libxkbcommon0 libxrandr2 && \
    rm -rf /var/lib/apt/lists/* && \
    rm -f /etc/ssh/ssh_host_*

# ttyd web terminal
ARG TARGETARCH
ARG TTYD_VERSION=1.7.7
RUN set -eu; \
    case "${TARGETARCH:-amd64}" in \
        amd64) ttyd_arch="x86_64" ;; \
        arm64) ttyd_arch="aarch64" ;; \
        *) echo "Unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL --retry 3 -o /usr/local/bin/ttyd \
        "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${ttyd_arch}"; \
    chmod 0755 /usr/local/bin/ttyd; \
    ttyd --version

# Everything Hermes writes lives on the /opt/data volume:
#   /opt/data/hermes-agent   git checkout (managed by install.sh / hermes update)
#   /opt/data/data_dir       HERMES_HOME: config, .env, sessions, memories, tools
#   /opt/data                HOME (~/.local/bin/hermes launcher, ~/.config, ...)
ENV HOME=/opt/data \
    HERMES_HOME=/opt/data/data_dir \
    HERMES_INSTALL_DIR=/opt/data/hermes-agent \
    PATH=/opt/data/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# root's home is the volume too, so SSH / web-terminal shells pick up the
# installer's ~/.bashrc PATH entry and land next to the data. SSH sessions
# don't inherit the image ENV; pam_env reads /etc/environment.
RUN sed -i "s#^root:\([^:]*\):0:0:\([^:]*\):/root:#root:\1:0:0:\2:/opt/data:#" /etc/passwd && \
    printf 'HOME="%s"\nHERMES_HOME="%s"\nHERMES_INSTALL_DIR="%s"\nPATH="%s"\n' \
        "$HOME" "$HERMES_HOME" "$HERMES_INSTALL_DIR" "$PATH" > /etc/environment

COPY --chmod=0755 entrypoint.sh /opt/entrypoint.sh

WORKDIR /opt/data
EXPOSE 7681
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/opt/entrypoint.sh"]
