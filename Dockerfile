# ============================================================================
# hermes-agent-akash
#
# Thin Akash layer on top of the official Hermes Agent image. Upstream now
# ships a sealed, immutable install at /opt/hermes (pinned toolchain, prebuilt
# TUI/dashboard, s6-overlay supervision, non-root runtime user). We keep all
# of that and only add what Akash deployments need:
#
#   - env vars -> $HERMES_HOME/.env + config.yaml sync on every boot
#   - one-time migration of volumes created by the old (pre-v0.23) image
#   - optional SSH server
#   - optional ttyd web terminal (s6-supervised)
#   - default command: messaging gateway when tokens are set, else idle
#
# To update Hermes: bump HERMES_VERSION (an official release tag from
# https://hub.docker.com/r/nousresearch/hermes-agent/tags) and rebuild.
# ============================================================================
ARG HERMES_VERSION=v0.23.0
FROM nousresearch/hermes-agent:${HERMES_VERSION}

USER root

# ── SSH server (optional at runtime) ────────────────────────────────────────
RUN apt-get -o Acquire::Retries=3 update && \
    apt-get -o Acquire::Retries=3 install -y --no-install-recommends openssh-server && \
    rm -rf /var/lib/apt/lists/* && \
    rm -f /etc/ssh/ssh_host_*

# ── ttyd web terminal ───────────────────────────────────────────────────────
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

# ── Akash boot scripts ──────────────────────────────────────────────────────
# 00-akash-migrate runs before upstream's 01-hermes-setup (stage2 hook);
# 03-akash-config runs after it, once .env/config.yaml have been seeded.
COPY --chmod=0755 akash/ /opt/akash/
RUN ln -s /opt/akash/cont-init.d/00-akash-migrate /etc/cont-init.d/00-akash-migrate && \
    ln -s /opt/akash/cont-init.d/03-akash-config /etc/cont-init.d/03-akash-config && \
    cp -r /opt/akash/s6-rc.d/web-terminal /etc/s6-overlay/s6-rc.d/web-terminal && \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/web-terminal

# Keep the data layout of existing Akash deployments: user data has always
# lived in /opt/data/data_dir on the persistent volume.
ENV HERMES_HOME=/opt/data/data_dir

# SSH sessions don't inherit the image ENV. Snapshot the Hermes-relevant vars
# into /etc/environment (read by pam_env for every sshd session) so `hermes`
# resolves and uses the right HERMES_HOME over SSH too.
RUN env | grep -E '^(PATH|HERMES_[A-Z_]*|PLAYWRIGHT_BROWSERS_PATH|XDG_RUNTIME_DIR|PYTHONUNBUFFERED|PYTHONDONTWRITEBYTECODE)=' \
        | sed -E 's/^([^=]+)=(.*)$/\1="\2"/' > /etc/environment && \
    cat /etc/environment

EXPOSE 7681

# ENTRYPOINT is inherited from upstream (entrypoint-dispatch.sh -> s6 /init).
CMD ["/opt/akash/start.sh"]
