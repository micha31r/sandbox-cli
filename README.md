# sandbox

A small wrapper around Docker that gives an AI agent a container which can only
see **one folder**. It runs on macOS, Linux and Windows, and one command updates
everything in it:

- **Agents:** Claude Code and GitHub Copilot CLI
- **Python 3.14:** uv, ruff (lint and format), pyright (type checking)
- **Node.js LTS:** npm, pnpm and yarn (through corepack), TypeScript (`tsc`),
  `tsx`, ESLint, Prettier
- **Language servers** for agents' code intelligence plugins:
  `typescript-language-server` (projects on TypeScript 6 or older),
  `tsc --lsp --stdio` (TypeScript 7) and `pyright-langserver`
- **Tools:** git, the GitHub CLI, ripgrep, jq, tmux, build-essential and more

```
sandbox create [NAME] [--dir DIR]   create a sandbox for DIR (default: current folder)
sandbox shell  [NAME] [-- CMD...]   open a shell in it (or run CMD)
sandbox ls                          list every sandbox; pick one to open, update or delete
sandbox update [NAME...]            fetch the latest tools, move sandboxes onto them
sandbox delete NAME...              delete sandboxes (their folders are never touched)
sandbox registry [npm|pypi] [URL]   use a company package registry (see below)
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

Requires Docker and Python 3.9+ (standard library only). Clone this repository
to a folder where it can stay, and run the installer from there.

On macOS, Linux and WSL:

```sh
./install.sh             # or ./install.sh ~/bin to link into another directory
```

It links `sandbox` into `~/.local/bin` and, if that directory isn't on your
PATH yet, adds it in your shell's startup file (`.zshrc`, `.bashrc`, ...).
Keep the repository where it is: the script finds the `Dockerfile` through the
link.

On Windows, install [Docker Desktop](https://docs.docker.com/desktop/setup/install/windows-install/)
(with the WSL 2 backend) and Python, then run this in PowerShell, in the
repository's folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

It adds the folder to your user PATH. Open a new terminal and `sandbox` works
from PowerShell or cmd. It runs through `sandbox.cmd`, which starts the script
with the `py` launcher (or `python`). Use Windows Terminal for the `sandbox ls`
picker. If you work inside WSL instead, run `install.sh` there.

Both installers are safe to run again, and tell you if Docker or Python is
missing. The first `sandbox create` builds the image, which takes a few
minutes.

## Typical use

```sh
cd ~/code/my-app
sandbox create
sandbox shell                                          # a bash shell in /workspace/my-app
sandbox shell -- claude --dangerously-skip-permissions  # or run the agent directly
sandbox shell -- copilot --allow-all                    # or Copilot
```

## Updating

Nothing in the `Dockerfile` is pinned. Every build fetches the newest base
images and the latest release of each tool. The **built image is the pin**, so
new sandboxes start with whatever was current at your last update.

`sandbox update` rebuilds the image from scratch (`--pull --no-cache`) and
prints what changed:

```
New sandboxes now get:
  claude      2.1.270 -> 2.1.282
  copilot     1.0.88
  python      3.14.7
  node        24.21.0
  ...
```

It then recreates each sandbox on the new image (all of them, or only the ones
you name). A sandbox that's in use (an open shell or a running agent) is
skipped, so nothing gets killed. Run the update again later, or pass `--force`.

Recreating a sandbox keeps:

- **the folder**, which is bind-mounted from your machine;
- **the home directory** (`/home/agent`), a per-sandbox Docker volume that holds
  the Claude and Copilot logins and settings, shell history, git config,
  `uv tool` and `npm -g` installs.

Anything else is reset, such as packages the agent installed with
`sudo apt-get`. To keep a tool, add it to the `Dockerfile`.

The auto-updaters of Claude Code and Copilot CLI are off inside sandboxes
(`DISABLE_AUTOUPDATER=1`, `COPILOT_AUTO_UPDATE=false`), so they won't nag or
update themselves. `sandbox update` handles them. The image's
tools also come first on `PATH`, so a stray copy in the home volume (for
example from `claude install`) can't shadow a newer one.

## Customizing the image

Edit the `Dockerfile`, then run `sandbox update`. Install tools system-wide
(for example under `/usr/local`), not in `/home/agent`: an existing sandbox
keeps its own home volume, so it never sees what the image puts there. To
include a new tool in the version report, add a line to `sandbox-versions` in
the `Dockerfile`.

## Logging in

Each sandbox has its own home, so you log in once per sandbox and the login
survives updates. To skip that step, set a token in your shell profile (or,
on Windows, as a user environment variable) and `sandbox shell` forwards it
into the sandbox:

- **Claude Code:** run `claude setup-token` on your machine and set
  `CLAUDE_CODE_OAUTH_TOKEN`, or set `ANTHROPIC_API_KEY`.
- **Copilot CLI:** create a fine-grained personal access token with the
  "Copilot Requests" permission and set `COPILOT_GITHUB_TOKEN`. Otherwise run
  `copilot` and use `/login`.

`GH_TOKEN` and `GITHUB_TOKEN` are *not* forwarded, since they would give the
agent your GitHub access; run `gh auth login` inside a sandbox if you want
that. Your git `user.name`, `user.email` and `core.autocrlf` are copied in at
creation, so the agent can commit.

## Company package registries

If your network blocks the public npm registry or PyPI, so you have to use
your company's mirror, give `sandbox` its address:

```sh
sandbox registry npm https://artifactory.example.com/api/npm/npm/
sandbox registry pypi https://artifactory.example.com/api/pypi/pypi/simple
```

Every new shell in every sandbox then uses them: npm, pnpm, yarn and corepack
use the npm registry, and pip and uv use the PyPI one. The image build uses the
npm registry too, to install Copilot CLI, TypeScript and the other npm tools,
so set it before your first `sandbox create`.

`sandbox registry` shows the current settings, and `sandbox registry npm
--unset` goes back to the public registry. They're saved in
`~/.config/sandbox-cli/config.json` (`%APPDATA%\sandbox-cli\config.json` on
Windows).

If the registry needs a login, run `npm login --registry URL` inside a
sandbox. The login is kept in the sandbox's home. The image build doesn't log
in, so it needs a registry that allows downloads without one.

## What the agent can and can't reach

- From your machine it sees only the folder, mounted at `/workspace/<folder>`.
  The rest of the container (`/usr`, `/etc`, `/home/agent`, ...) is the
  sandbox's own Linux system and its private home volume, not your files.
  There's no access to the rest of your filesystem, other sandboxes, or the
  Docker socket.
- It runs as a non-root user whose uid matches yours, so files it creates
  belong to you (on Windows, where files have no uid, it's 1000). It has
  passwordless `sudo` inside the container.
- **Network access is unrestricted.** It needs that for the Claude API, pip
  and npm.
- `sandbox create` refuses to mount your home directory, or a folder that
  contains it, unless you pass `--force`.

## Notes

- `.venv` and `node_modules` in the folder contain platform-specific binaries.
  If you also use them from macOS or Windows, the sandbox (Linux) and your
  machine will keep rebuilding each other's copies.
- The global `eslint` and `prettier` are for quick use. In a project, the
  agent should run the project's own versions (`npm run lint`, `npx eslint`).
- On Windows, a folder on a Windows drive is shared into the Linux VM, which
  makes file access in the sandbox noticeably slower than on macOS or Linux.
  For big projects, keep them in the WSL filesystem and run `sandbox` from
  WSL.
- Each update leaves about 1.5 GB of Docker build cache. Docker reclaims it on
  its own over time, or immediately with `docker builder prune`.
