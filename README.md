# sandbox

A small wrapper around Docker that gives an AI agent a container which can only
see **one folder**. It comes with Python 3.14, Claude Code, Node.js LTS, uv, git
and the GitHub CLI, and one command updates all of them.

```
sandbox create [NAME] [--dir DIR]   create a sandbox for DIR (default: current folder)
sandbox shell  [NAME] [-- CMD...]   open a shell in it (or run CMD)
sandbox ls                          list every sandbox; pick one to open, update or delete
sandbox update [NAME...]            fetch the latest tools, move sandboxes onto them
sandbox delete NAME...              delete sandboxes (their folders are never touched)
```

Every command works from any directory. `NAME` defaults to the folder's name
for `create`. For `shell` it defaults to the sandbox that owns the current
folder, so `cd ~/code/app && sandbox shell` just works.

`sandbox ls` lists all sandboxes, wherever their folders are, and shows which
ones are on an outdated image. In a terminal you can act on them directly:

```
NAME          STATUS   IMAGE     FOLDER
api           running  current   /Users/you/code/api
finance-book  running  outdated  /Users/you/code/finance-book
↑/↓ select · enter: open shell · u: update · d: delete · q: quit
```

Deleting asks for confirmation. When piped (`sandbox ls | grep outdated`), it
prints only the table.

## Install

Requires Docker and Python 3.9+ (standard library only).

```sh
ln -s "$PWD/sandbox" ~/.local/bin/sandbox   # any directory on your PATH
```

Keep the symlink. The script finds the `Dockerfile` through it. The first
`sandbox create` builds the image, which takes a couple of minutes.

## Typical use

```sh
cd ~/code/my-app
sandbox create
sandbox shell                                          # a bash shell in /workspace/my-app
sandbox shell -- claude --dangerously-skip-permissions  # or run the agent directly
```

## Updating

Nothing in the `Dockerfile` is pinned. Every build fetches the newest base
images and the latest release of each tool. The **built image is the pin**, so
new sandboxes start with whatever was current at your last update.

`sandbox update` rebuilds the image from scratch (`--pull --no-cache`) and
prints what changed:

```
New sandboxes now get:
  claude  2.1.270 -> 2.1.282
  python  3.14.7
  node    24.21.0
  ...
```

It then recreates each sandbox on the new image (all of them, or only the ones
you name). A sandbox that's in use (an open shell or a running agent) is
skipped, so nothing gets killed. Run the update again later, or pass `--force`.

Recreating a sandbox keeps:

- **the folder**, which is bind-mounted from your machine;
- **the home directory** (`/home/agent`), a per-sandbox Docker volume that holds
  the Claude login and settings, shell history, git config, `uv tool` and
  `npm -g` installs.

Anything else is reset, such as packages the agent installed with
`sudo apt-get`. To keep a tool, add it to the `Dockerfile`.

Claude Code's auto-updater is off inside sandboxes (`DISABLE_AUTOUPDATER=1`),
so it won't nag or update itself. `sandbox update` handles it. The image's
tools also come first on `PATH`, so a stray copy in the home volume (for
example from `claude install`) can't shadow a newer one.

## Customizing the image

Edit the `Dockerfile`, then run `sandbox update`. Install tools system-wide
(for example under `/usr/local`), not in `/home/agent`: an existing sandbox
keeps its own home volume, so it never sees what the image puts there. To
include a new tool in the version report, add a line to `sandbox-versions` in
the `Dockerfile`.

## Logging in to Claude

Each sandbox has its own home, so you log in once per sandbox and the login
survives updates. To skip that step, run `claude setup-token` on your machine
and `export CLAUDE_CODE_OAUTH_TOKEN=...` in your shell profile. `sandbox shell`
forwards `CLAUDE_CODE_OAUTH_TOKEN` and `ANTHROPIC_API_KEY` into the sandbox
when they're set. Your git `user.name` and `user.email` are copied in at
creation, so the agent can commit.

## What the agent can and can't reach

- From your machine it sees only the folder, mounted at `/workspace/<folder>`.
  The rest of the container (`/usr`, `/etc`, `/home/agent`, ...) is the
  sandbox's own Linux system and its private home volume, not your files.
  There's no access to the rest of your filesystem, other sandboxes, or the
  Docker socket.
- It runs as a non-root user whose uid matches yours, so files it creates
  belong to you. It has passwordless `sudo` inside the container.
- **Network access is unrestricted.** It needs that for the Claude API, pip
  and npm.
- `sandbox create` refuses to mount your home directory, or a folder that
  contains it, unless you pass `--force`.

## Notes

- `.venv` and `node_modules` in the folder contain platform-specific binaries.
  If you also use them from macOS, the sandbox (Linux) and your machine will
  keep rebuilding each other's copies.
- Each update leaves about 1.5 GB of Docker build cache. Docker reclaims it on
  its own over time, or immediately with `docker builder prune`.
