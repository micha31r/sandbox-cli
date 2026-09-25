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
FROM ghcr.io/astral-sh/ruff:latest AS ruff

FROM python:${PYTHON_VERSION}-slim-trixie

# System packages, plus the GitHub CLI from its official apt repo.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl file git jq less nano \
        openssh-client procps ripgrep sudo tmux tree unzip vim wget zip; \
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

# Global npm tools. These go under /usr/local: the ENV below that points
# `npm install -g` at the home volume only applies after this point.
#   @github/copilot   GitHub Copilot CLI (`copilot`)
#   typescript, tsx   `tsc`, and `tsx` to run .ts files directly
#   eslint, prettier  JS/TS linter and formatter
#   typescript-language-server, pyright
#                     language servers for code intelligence plugins. The first
#                     wraps the tsserver of a project's own TypeScript 6 or older;
#                     TypeScript 7 has none, and serves LSP itself (`tsc --lsp`).
#                     `pyright` also type-checks from the command line.
#   corepack          provides `pnpm` and `yarn`, at the version a project's
#                     package.json asks for
RUN npm install --global \
        @github/copilot corepack eslint prettier pyright tsx typescript \
        typescript-language-server \
 && corepack enable \
 && rm -rf /root/.npm

# uv and uvx, and ruff (Python linter and formatter).
COPY --from=uv /uv /uvx /usr/local/bin/
COPY --from=ruff /ruff /usr/local/bin/

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
echo "copilot $(copilot --version | head -n1 | grep -oE '[0-9]+(\.[0-9]+)+')"
echo "python $(python3 --version | cut -d' ' -f2)"
echo "node $(node --version | tr -d v)"
echo "npm $(npm --version)"
echo "typescript $(tsc --version | cut -d' ' -f2)"
echo "tsx $(tsx --version | head -n1 | cut -d' ' -f2 | tr -d v)"
echo "eslint $(eslint --version | tr -d v)"
echo "prettier $(prettier --version)"
echo "pyright $(pyright --version | cut -d' ' -f2)"
echo "uv $(uv --version | cut -d' ' -f2)"
echo "ruff $(ruff --version | cut -d' ' -f2)"
echo "git $(git --version | cut -d' ' -f3)"
echo "gh $(gh --version | head -n1 | cut -d' ' -f3)"
EOF

# DISABLE_AUTOUPDATER, COPILOT_AUTO_UPDATE: Claude Code and Copilot CLI are
#   updated by `sandbox update`, not by themselves.
# COREPACK_ENABLE_DOWNLOAD_PROMPT: fetch a project's pnpm/yarn without asking
#   (the prompt would block an agent).
# UV_LINK_MODE: uv's cache (home volume) and your .venv (mounted folder) live on
#   different filesystems, so hardlinking always fails; copy without warning.
# NPM_CONFIG_PREFIX: `npm install -g` goes to the home volume, no sudo needed.
# PATH: the home volume's bin dirs come *last*, so a copy installed there
#   (e.g. by `claude install`) can never shadow the image's newer one.
ENV LANG=C.UTF-8 \
    DISABLE_AUTOUPDATER=1 \
    COPILOT_AUTO_UPDATE=false \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    UV_LINK_MODE=copy \
    NPM_CONFIG_PREFIX=/home/agent/.npm-global \
    PATH=$PATH:/home/agent/.local/bin:/home/agent/.npm-global/bin

USER agent
WORKDIR /home/agent
CMD ["sleep", "infinity"]
