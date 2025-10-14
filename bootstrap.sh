#!/bin/bash
set -euo pipefail
cd $(dirname $0)

#------ Probe ------------------------------------------------------------------------------------------------
echo "Probing environment..."

HOST=$(hostname)
LINUX=false
MACOS=false
NIX=false
[[ "$(uname -s)" == "Darwin" ]] && MACOS=true
[[ "$(uname -s)" == "Linux" ]]  && LINUX=true
[[ -x "$(command -v nix)" ]] && NIX=true

echo "  Host: $HOST"
$MACOS && echo "  OS: MacOS"
$LINUX && echo "  OS: Linux"
$NIX && echo "  Packages: Nix"

#------ Bootstrap --------------------------------------------------------------------------------------------
if $MACOS; then
    # Setup nix
    if ! command -v nix >/dev/null; then
        curl -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm --no-modify-profile
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    fi
    NIX=true

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
    [ -d /Applications/Neovide.app ]   || brew install --cask neovide                    # Neovim GUI

    # Update shell
    if [ "$SHELL" == "/bin/zsh" ]; then
        sudo sh -c 'echo "$HOME/.nix-profile/bin/fish" >> /etc/shells'
        chsh -s "$HOME/.nix-profile/bin/fish"
    fi
fi
if $NIX; then
    # Rust
    rustup default | grep -q nightly || rustup default nightly
fi

#------ Configs ----------------------------------------------------------------------------------------------
echo -e "\nSymlinking configs..."

# Install config symlinks
install() {
    SRC=$1
    DST=~/.config/$2
    echo "  $SRC -> $DST"
    mkdir -p $(dirname $DST)
    ln -sf $PWD/config/$SRC $DST
}

install tmux.conf tmux/tmux.conf
install gitconfig git/config
install gitignore git/ignore
install nvim/init.lua nvim/init.lua
install nvim/lib.lua nvim/lua/lib.lua

if $MACOS; then
    install fish_macos.fish fish/conf.d/macos.fish
    install ghostty.conf ghostty/config
    install neovide.toml neovide/config.toml
    install aerospace.toml aerospace/aerospace.toml
fi
if $NIX; then
    install fish.fish fish/config.fish
    install direnv.toml direnv.toml
    install starship.toml starship.toml
fi

echo -e "\n✅ Dots installed!"
