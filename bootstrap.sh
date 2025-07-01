#!/bin/bash
set -euo pipefail
cd $(dirname $0)

MACOS=false
[[ "$(uname -s)" == "Darwin" ]] && MACOS=true

# Bootstrap
if $MACOS; then
    # Setup nix
    if ! command -v nix >/dev/null; then
        curl -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm --no-modify-profile
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    fi

    # Setup homebrew
    if ! command -v brew >/dev/null; then
        bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        export PATH=/opt/homebrew/bin:$PATH
    fi

    # Install nix tools if not already
    if ! command -v fish >/dev/null; then
        nix profile install .#dots-macos
    fi
    # Upgrade nix tools if flake.nix has changes
    if ! git diff --quiet flake.nix; then
        git add flake.nix
        nix profile upgrade dots-macos
    fi

    # Install homebrew apps
    [ -d /Applications/Secretive.app ] || brew install --cask secretive                  # SSH pubkey auth via TPM
    [ -d /Applications/Ghostty.app ]   || brew install --cask ghostty                    # Terminal
    [ -d /Applications/AeroSpace.app ] || brew install --cask nikitabobko/tap/aerospace  # Window manager
    [ -d /Applications/Zed.app ]       || brew install --cask zed                        # Editor

    # Update shell
    if [ "$SHELL" == "/bin/zsh" ]; then
        sudo sh -c 'echo "$HOME/.nix-profile/bin/fish" >> /etc/shells'
        chsh -s "$HOME/.nix-profile/bin/fish"
    fi
fi

# Rust
rustup default | grep -q nightly || rustup default nightly

# Install config symlinks
install() {
    SRC=$1
    DST=~/.config/$2
    echo "$SRC -> $DST"
    mkdir -p $(dirname $DST)
    ln -sf $PWD/config/$SRC $DST
}

install fish.fish fish/config.fish
install tmux.conf tmux/tmux.conf
install gitconfig git/config
install gitignore git/ignore
install direnv.toml direnv.toml
install starship.toml starship.toml

if $MACOS; then
    install fish_macos.fish fish/conf.d/macos.fish
    install aerospace.toml aerospace/aerospace.toml
fi

echo "✅ dotfiles installed!"
