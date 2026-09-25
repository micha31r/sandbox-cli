# syntax=docker/dockerfile:1
#
# The image every sandbox runs.
#
# Nothing here is pinned. Each build pulls the newest base images and the
# latest release of every tool. `sandbox update` rebuilds it from scratch
# (--pull --no-cache), so the built image *is* the pin: new sandboxes get
# whatever was current at the last update.
#
# To add a tool, edit this file and run `sandbox update`. Install tools
# system-wide, not under /home/agent. Each sandbox's home is a persistent
# volume, so anything the image puts there never reaches existing sandboxes.

ARG PYTHON_VERSION=3.14

FROM node:lts-trixie-slim AS node
FROM ghcr.io/astral-sh/uv:latest AS uv

FROM python:${PYTHON_VERSION}-slim-trixie

# System packages, plus the GitHub CLI from its official apt repo.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl file git jq less nano \
        openssh-client procps ripgrep sudo tree unzip vim wget zip; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
        https://cli.github.com/packages/githubcli-archive-keyring.gpg; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends gh; \
    rm -rf /var/lib/apt/lists/*

# Node.js (current LTS) and npm, taken from the official image.
COPY --from=node /usr/local/bin/node /usr/local/bin/
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# uv and uvx.
COPY --from=uv /uv /uvx /usr/local/bin/

# Claude Code. The official installer puts it under $HOME; move the binary out
# so the image owns it (and `sandbox update` can replace it).
RUN curl -fsSL https://claude.ai/install.sh | bash \
 && install -m 0755 "$(readlink -f /root/.local/bin/claude)" /usr/local/bin/claude \
 && rm -rf /root/.local /root/.claude /root/.claude.json

# Non-root user with the host user's uid/gid, so files the agent creates in the
# mounted folder belong to you. Passwordless sudo lets it apt-get install
# extras; those last until the sandbox is next updated.
ARG USER_UID=1000
ARG USER_GID=1000
RUN set -eux; \
    existing="$(getent passwd "$USER_UID" | cut -d: -f1)"; \
    if [ -n "$existing" ]; then userdel -r "$existing"; fi; \
    getent group "$USER_GID" >/dev/null || groupadd -g "$USER_GID" agent; \
    useradd -m -s /bin/bash -u "$USER_UID" -g "$USER_GID" agent; \
    echo 'agent ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/agent; \
    chmod 0440 /etc/sudoers.d/agent; \
    git config --system safe.directory '*'; \
    git config --system init.defaultBranch main; \
    echo sandbox > /etc/debian_chroot

# `sandbox update` runs this on the old and new image to show what changed.
# Add a line when you add a tool.
COPY --chmod=0755 <<'EOF' /usr/local/bin/sandbox-versions
#!/bin/sh
echo "claude $(claude --version | cut -d' ' -f1)"
echo "python $(python3 --version | cut -d' ' -f2)"
echo "node $(node --version | tr -d v)"
echo "uv $(uv --version | cut -d' ' -f2)"
echo "git $(git --version | cut -d' ' -f3)"
echo "gh $(gh --version | head -n1 | cut -d' ' -f3)"
EOF

# DISABLE_AUTOUPDATER: Claude Code is updated by `sandbox update`, not by itself.
# UV_LINK_MODE: uv's cache (home volume) and your .venv (mounted folder) live on
#   different filesystems, so hardlinking always fails; copy without warning.
# NPM_CONFIG_PREFIX: `npm install -g` goes to the home volume, no sudo needed.
# PATH: the home volume's bin dirs come *last*, so a copy installed there
#   (e.g. by `claude install`) can never shadow the image's newer one.
ENV LANG=C.UTF-8 \
    DISABLE_AUTOUPDATER=1 \
    UV_LINK_MODE=copy \
    NPM_CONFIG_PREFIX=/home/agent/.npm-global \
    PATH=$PATH:/home/agent/.local/bin:/home/agent/.npm-global/bin

USER agent
WORKDIR /home/agent
CMD ["sleep", "infinity"]
