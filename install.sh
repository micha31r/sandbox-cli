#!/bin/sh
# Puts `sandbox` on your PATH on macOS, Linux and WSL (on Windows itself, use
# install.ps1). Links the script into ~/.local/bin, or the directory you pass,
# and adds that directory to your shell's startup file if it isn't on your
# PATH yet. Safe to run again.
#
#   ./install.sh [BIN_DIR]
set -eu

case $(uname -s) in
    MINGW* | MSYS* | CYGWIN*)
        echo "install.sh: on Windows, run install.ps1 instead" >&2
        exit 1 ;;
esac

repo=$(cd "$(dirname "$0")" && pwd -P)
mkdir -p "${1:-$HOME/.local/bin}"
bin=$(cd "${1:-$HOME/.local/bin}" && pwd)
link=$bin/sandbox

# A symlink, not a copy: the script finds the Dockerfile through it.
if [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "install.sh: $link already exists and isn't a symlink; move it and run again" >&2
    exit 1
fi
chmod +x "$repo/sandbox"
ln -sf "$repo/sandbox" "$link"
echo "Linked $link -> $repo/sandbox"

case ":$PATH:" in
    *":$bin:"*)
        found=$(command -v sandbox || true)
        if [ "$found" != "$link" ]; then
            echo "Note: \`sandbox\` runs $found, which comes before $bin on your PATH"
        fi ;;
    *)
        # Write $HOME rather than your home's path, so the line reads the usual way.
        case $bin in
            "$HOME"/*) dir="\$HOME/${bin#"$HOME"/}" ;;
            *) dir=$bin ;;
        esac
        case $(basename "${SHELL:-sh}") in
            zsh) profile=${ZDOTDIR:-$HOME}/.zshrc ;;
            bash)
                # macOS terminals start login shells, which read .bash_profile.
                if [ "$(uname -s)" = Darwin ]; then profile=$HOME/.bash_profile; else profile=$HOME/.bashrc; fi ;;
            fish) profile=${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish ;;
            *) profile=$HOME/.profile ;;
        esac
        case $profile in
            *.fish) line="fish_add_path \"$dir\"" ;;
            *) line="export PATH=\"$dir:\$PATH\"" ;;
        esac
        if ! grep -qsxF "$line" "$profile"; then
            mkdir -p "$(dirname "$profile")"
            printf '\n# Added by sandbox-cli install.sh\n%s\n' "$line" >> "$profile"
        fi
        echo "Added $bin to your PATH in $profile; open a new terminal to use \`sandbox\`" ;;
esac

command -v docker >/dev/null 2>&1 ||
    echo "Note: sandbox needs Docker, which isn't on your PATH (https://docs.docker.com/get-docker/)"
python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))' 2>/dev/null ||
    echo "Note: sandbox needs Python 3.9 or newer as \`python3\`"
