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
command -v nix >/dev/null && NIX=true

echo "  Host: $HOST"
$MACOS && echo "  OS: MacOS"
$LINUX && echo "  OS: Linux"

#------ Bootstrap --------------------------------------------------------------------------------------------
if $MACOS; then
    defaults write -g InitialKeyRepeat -int 14
    defaults write -g KeyRepeat -int 1

    # Setup nix
    if ! $NIX; then
        echo "  Nix: installing..."
        curl -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm --no-modify-profile
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
        echo "  Nix: OK"
        NIX=true
    else
        echo "  Nix: OK"
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
    if [ "$(cat ~/.cache/dots_commit 2>/dev/null)" != "$(git rev-parse HEAD)" ]; then
      nix profile upgrade dots-macos && \
        git rev-parse HEAD > ~/.cache/dots_commit
    elif ! git diff --quiet flake.nix; then
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
        echo -e "  Shell: please re-login to update"
    else
        echo "  Shell: fish"
    fi
fi
if $LINUX; then
    if ! $NIX; then
        if command -v cargo >/dev/null; then
            echo "  Nix: installing..."

            cargo install nix-user-chroot
            mkdir -p ~/.config/nix
            mkdir -pm 0755 ~/.nix
            ~/.cargo/bin/nix-user-chroot ~/.nix bash -c "curl -L https://nixos.org/nix/install | bash"

            echo "extra-experimental-features = nix-command flakes" > ~/.config/nix/nix.conf
            echo "[ ! -d /nix ] && exec ~/.cargo/bin/nix-user-chroot ~/.nix bash -l" >> ~/.bashrc

            echo -e "\nNix: please re-login to continue install"
            exit 1
        else
            echo"  Nix: missing cargo"
        fi
    else
        echo "  Nix: ok"
    fi

    # Install nix tools if not already
    if ! command -v fish >/dev/null; then
        nix profile install .#dots
    fi
    # Upgrade nix tools if flake.nix has changes
    if [ "$(cat ~/.cache/dots_commit 2>/dev/null)" != "$(git rev-parse HEAD)" ]; then
      nix profile upgrade dots && \
        git rev-parse HEAD > ~/.cache/dots_commit
    elif ! git diff --quiet flake.nix; then
        git add flake.nix
        nix profile upgrade dots
    fi

    # Update shell
    if [ "$SHELL" == "/bin/bash" ]; then
        if ! grep -q "NOFISH" ~/.bashrc; then
            echo "[ ! -v NOFISH ] && exec ~/.nix-profile/bin/fish" >> ~/.bashrc
        fi
        echo -e "  Shell: please re-login to update"
    else
        echo "  Shell: fish"
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
    if [[ "$2" == "$(realpath ~)"* ]]; then
        DST=$2
    else
        DST=~/.config/$2
    fi
    echo "  $SRC -> $DST"
    mkdir -p $(dirname $DST)
    ln -sf $PWD/config/$SRC $DST
}

install tmux.conf tmux/tmux.conf
install gitconfig git/config
install gitignore git/ignore
install nvim/init.lua nvim/init.lua
install nvim/lib.lua nvim/lua/lib.lua
install nvim/setup.lua nvim/lua/setup.lua
install nvim/framework.lua nvim/lua/framework.lua
install fish.fish fish/config.fish

if $MACOS; then
    install fish_macos.fish fish/conf.d/macos.fish
    install ghostty.conf ghostty/config
    install neovide.toml neovide/config.toml
    install aerospace.toml aerospace/aerospace.toml
fi
if $LINUX; then
    install fish_linux.fish fish/conf.d/linux.fish
fi
if $NIX; then
    install direnv.toml direnv.toml
    install starship.toml starship.toml
fi

echo -e "\n✅ Dots installed!"
