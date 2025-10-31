#!/bin/bash
set -euo pipefail
cd $(dirname $0)
ROOT=$PWD
PKGS=$ROOT/pkgs
TEMP=$ROOT/temp

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
    #defaults write -g InitialKeyRepeat -int 14
    #defaults write -g KeyRepeat -int 1

    # Setup homebrew
    # if ! command -v brew >/dev/null; then
    #     bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    #     export PATH=/opt/homebrew/bin:$PATH
    # fi

    # Install homebrew apps
    [ -d /Applications/Secretive.app ] || brew install --cask secretive                  # SSH pubkey auth via TPM
    [ -d /Applications/Ghostty.app ]   || brew install --cask ghostty                    # Terminal
    [ -d /Applications/AeroSpace.app ] || brew install --cask nikitabobko/tap/aerospace  # Window manager
    [ -d /Applications/Zed.app ]       || brew install --cask zed                        # Editor
    [ -d /Applications/Neovide.app ]   || brew install --cask neovide                    # Neovim GUI

    # Update shell
    #if [ "$SHELL" == "/bin/zsh" ]; then
    #    sudo sh -c 'echo "$HOME/.nix-profile/bin/fish" >> /etc/shells'
    #    chsh -s "$HOME/.nix-profile/bin/fish"
    #    echo -e "  Shell: please re-login to update"
    #else
    #    echo "  Shell: fish"
    #fi
fi
#if $LINUX; then
#    # Update shell
#    if [ "$SHELL" == "/bin/bash" ]; then
#        if ! grep -q "NOFISH" ~/.bashrc; then
#            echo "[ ! -v NOFISH ] && exec ~/.nix-profile/bin/fish" >> ~/.bashrc
#        fi
#        echo -e "  Shell: please re-login to update"
#    else
#        echo "  Shell: fish"
#    fi
#fi
#if $NIX; then
#    # Rust
#    rustup default | grep -q nightly || rustup default nightly
#fi

#------ Packages ---------------------------------------------------------------------------------------------

if $MACOS; then
    ARCH1=aarch64-apple-darwin
    ARCH2=darwin-arm64
    ARCH3=macos-arm64
    ARCH4=mac
    ARCH5=darwin-arm64
elif $LINUX; then
    ARCH1=x86_64-unknown-linux-musl
    ARCH2=linux-amd64
    ARCH3=linux-x86_64
    ARCH4=linux
    ARCH5=linux-x64
else
    echo "Unsupported OS!"
fi

mkdir -p $PKGS $TEMP

dirty() {
    local ver=$1 dir=$2
    ! grep -qxF $ver $dir/version 2>/dev/null
}
undirty() {
    local ver=$1 dir=$2
    echo $ver > $dir/version
}

echo -e "\nInstalling packages..."

python!() {
    local ver=3.14.0 dir=$PKGS/python
    if dirty $ver $dir; then
        curl -L https://www.python.org/ftp/python/${ver}/Python-${ver}.tgz \
            | tar xzf - -C $TEMP

        pushd $TEMP/Python-$ver
        ./configure --prefix=$dir --disable-test-modules
        make -j
        make install
        popd

        undirty $ver $dir
    fi
}
python!
PATH="$PKGS/python/bin:$PATH"

clang!() {
    if $LINUX; then
        local ver=21.1.0 dir=$PKGS/clang
        if dirty $ver $dir; then
            rm -rf $dir
            curl -L https://github.com/llvm/llvm-project/releases/download/llvmorg-${ver}/llvm-project-${ver}.src.tar.xz \
                | tar xJf - -C $TEMP

            local build=$TEMP/clang-build
            cmake -S $TEMP/llvm-project-${ver}.src/llvm -B $build \
                -DCMAKE_INSTALL_PREFIX=$dir \
                -DLLVM_ENABLE_PROJECTS="clang;clang-tools-extra;compiler-rt" \
                -DLLVM_ENABLE_RUNTIMES="libunwind;libcxxabi;libcxx" \
                -DLLVM_ENABLE_LLD=OFF \
                -DLLVM_TARGETS_TO_BUILD="X86" \
                -DCMAKE_BUILD_TYPE=Release \

            cmake --build $build -j8
            cmake --install $build

            undirty $ver $dir
        fi
    fi
}
clang!
PATH="$PKGS/clang/bin:$PATH"

clang-rt() {
    if $LINUX; then
        local ver=21.1.0 dir=$PKGS/clang-rt
        if dirty $ver $dir; then
            rm -rf $dir

            curl -L https://github.com/llvm/llvm-project/releases/download/llvmorg-${ver}/llvm-project-${ver}.src.tar.xz \
                | tar xJf - -C $TEMP

            local build=$TEMP/clang-rt-build
            cmake -S $TEMP/llvm-project-${ver}.src/runtimes \
                -B $build \
                -DCMAKE_INSTALL_PREFIX=$PKGS/clang-rt \
                -DCMAKE_C_COMPILER=clang \
                -DCMAKE_CXX_COMPILER=clang++ \
                -DLLVM_ENABLE_RUNTIMES="libunwind;libcxxabi;libcxx" \
                -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld" \
                -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld" \
                -DCMAKE_MODULE_LINKER_FLAGS="-fuse-ld=lld" \
                -DCMAKE_BUILD_TYPE=Release

            cmake --build $build -j
            cmake --install $build

            undirty $ver $dir
        fi
    fi
}
clang-rt

cmake!() {
    local ver=3.31.9 dir=$PKGS/cmake
    if dirty $ver $dir; then
        rm -rf $dir
        mkdir $dir
        if $MACOS; then
            curl -L https://github.com/Kitware/CMake/releases/download/v${ver}/cmake-${ver}-macos-universal.tar.gz \
                | tar xzf - -C $TEMP
            mv $TEMP/cmake-${ver}-macos-universal/CMake.app/Contents/{bin,share} $dir
            rm -f $dir/bin/cmake-gui
        elif $LINUX; then
            curl -L https://github.com/Kitware/CMake/releases/download/v${ver}/cmake-${ver}-linux-x86_64.tar.gz \
                | tar xzf - -C $TEMP
            mv $TEMP/cmake-${ver}-linux-x86_64/{bin,share} $dir
        fi
        undirty $ver $dir
    fi
}
cmake!
PATH="$PKGS/cmake/bin:$PATH"

rust() {
    if [ ! -d ~/.cargo ]; then
        if $MACOS; then
            curl -L https://static.rust-lang.org/rustup/dist/aarch64-apple-darwin/rustup-init -o $TEMP/rustup-init
            chmod +x $TEMP/rustup-init
            $TEMP/rustup-init --default-toolchain nightly --no-modify-path -y
        elif $LINUX; then
            curl -L https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init -o $TEMP/rustup-init
            chmod +x $TEMP/rustup-init
            $TEMP/rustup-init --default-toolchain nightly --no-modify-path -y
        fi
    fi
}
rust
PATH="$HOME/.cargo/bin:$PATH"

dotnet!() {
    if $LINUX; then
        local ver10=10.0.100-rc.2.25502.107 ver9=9.0.306 ver8=8.0.415 dir=$PKGS/dotnet
        if dirty $ver10 $dir; then
            rm -rf $dir
            mkdir -p $dir/bin
            curl -L https://builds.dotnet.microsoft.com/dotnet/Sdk/${ver8}/dotnet-sdk-${ver8}-linux-x64.tar.gz | tar xzf - -C $dir
            curl -L https://builds.dotnet.microsoft.com/dotnet/Sdk/${ver9}/dotnet-sdk-${ver9}-linux-x64.tar.gz | tar xzf - -C $dir
            curl -L https://builds.dotnet.microsoft.com/dotnet/Sdk/${ver10}/dotnet-sdk-${ver10}-linux-x64.tar.gz | tar xzf - -C $dir
            ln -sfr $dir/dotnet $dir/bin/
            undirty $ver10 $dir
        fi
    fi
}
dotnet!
PATH="$PKGS/dotnet/bin:$PATH"

fish() {
    local ver=4.1.2 dir=$PKGS/fish

    if dirty $ver $dir; then
        rm -rf $dir
        mkdir -p $dir
        curl -L https://github.com/fish-shell/fish-shell/releases/download/${ver}/fish-${ver}.tar.xz \
            | tar xJf - -C $TEMP

        local build=$TEMP/fish-build
        cmake -S $TEMP/fish-$ver -B $build -DCMAKE_INSTALL_PREFIX=$dir
        cmake --build $build -j
        cmake --install $build
        undirty $ver $dir
    fi
}
fish

starship() {
    local ver=1.24.0 dir=$PKGS/starship
    if dirty $ver $dir; then
        mkdir -p $dir/bin
        curl -L https://github.com/starship/starship/releases/download/v${ver}/starship-${ARCH1}.tar.gz \
            | tar xzf - -C $dir/bin
        undirty $ver $dir
    fi
}
starship

zoxide() {
    local ver=0.9.8 dir=$PKGS/zoxide
    if dirty $ver $dir; then
        mkdir -p $dir/bin $TEMP/zoxide
        curl -L https://github.com/ajeetdsouza/zoxide/releases/download/v${ver}/zoxide-${ver}-${ARCH1}.tar.gz \
            | tar xzf - -C $TEMP/zoxide
        cp $TEMP/zoxide/zoxide $dir/bin
        undirty $ver $dir
    fi
}
zoxide

direnv() {
    local ver=2.37.1 dir=$PKGS/direnv
    if dirty $ver $dir; then
        mkdir -p $dir/bin
        curl -L https://github.com/direnv/direnv/releases/download/v${ver}/direnv.${ARCH2} \
            -o $dir/bin/direnv
        chmod +x $dir/bin/direnv
        undirty $ver $dir
    fi
}
direnv

eza() {
    local ver=0.23.4 dir=$PKGS/eza
    if dirty $ver $dir; then
        rm -rf $dir
        curl -L https://github.com/eza-community/eza/archive/refs/tags/v${ver}.tar.gz \
            | tar -xzf - -C $TEMP
        mkdir -p $dir
        cargo install --path $TEMP/eza-$ver --root $dir
        undirty $ver $dir
    fi
}
eza

libevent() {
    local ver=2.1.12-stable dir=$PKGS/libevent
    if dirty $ver $dir; then
        rm -rf $dir
        curl -L https://github.com/libevent/libevent/releases/download/release-${ver}/libevent-${ver}.tar.gz \
            | tar -xzf - -C $TEMP
        local build=$TEMP/libevent-build
        cmake -S $TEMP/libevent-$ver -B $build -DCMAKE_INSTALL_PREFIX=$dir
        cmake --build $build -j
        cmake --install $build
        undirty $ver $dir
    fi
}
libutf8proc() {
    if $MACOS; then
        local ver=2.11.0 dir=$PKGS/libutf8proc
        if dirty $ver $dir; then
            rm -rf $dir
            curl -L https://github.com/JuliaStrings/utf8proc/archive/refs/tags/v${ver}.tar.gz \
                | tar -xzf - -C $TEMP
            local build=$TEMP/utf8proc-${ver}/build
            cmake -S $build/.. -B $build -DCMAKE_INSTALL_PREFIX=$dir
            cmake --build $build -j
            cmake --install $build
            undirty $ver $dir
        fi
    fi
}
tmux() {
    local ver=3.5a dir=$PKGS/tmux
    if dirty $ver $dir; then
        rm -rf $dir

        libevent
        if $MACOS; then
            libutf8proc
        fi

        curl -L https://github.com/tmux/tmux/releases/download/${ver}/tmux-${ver}.tar.gz \
            | tar -xzf - -C $TEMP

        pushd $TEMP/tmux-$ver
        local pkgs="" cflags="-I$PKGS/libevent/include" ldflags="-L$PKGS/libevent/lib" flags=""
        if $MACOS; then
            pkgs="$PKGS/libutf8proc/lib/pkgconfig"
            flags="--enable-utf8proc"
        fi
        ./configure --prefix=$dir CFLAGS="$cflags" LDFLAGS="$ldflags" PKG_CONFIG_PATH=$pkgs $flags
        make -j
        make install
        popd

        undirty $ver $dir
    fi
}
tmux

nvim() {
    local ver=0.11.4 dir=$PKGS/nvim
    if dirty $ver $dir; then
        rm -rf $dir
        curl -L https://github.com/neovim/neovim/releases/download/v${ver}/nvim-${ARCH3}.tar.gz \
            | tar -xzf - -C $TEMP
        mv $TEMP/nvim-$ARCH3 $dir
        undirty $ver $dir
    fi
}
nvim

codex() {
    local ver=0.52.0 dir=$PKGS/codex
    if dirty $ver $dir; then
        mkdir -p $dir/bin
        curl -L https://github.com/openai/codex/releases/download/rust-v${ver}/codex-${ARCH1}.tar.gz \
            | tar -xzf - -C $TEMP
        mv $TEMP/codex-$ARCH1 $dir/bin/codex
        undirty $ver $dir
    fi
}
codex

clangd() {
    local ver=21.1.0 dir=$PKGS/clangd
    if dirty $ver $dir; then
        rm -rf $dir
        curl -L https://github.com/clangd/clangd/releases/download/${ver}/clangd-${ARCH4}-${ver}.zip -o $TEMP/clangd.zip
        unzip $TEMP/clangd.zip -d $TEMP
        mv $TEMP/clangd_$ver $dir
        undirty $ver $dir
    fi
}
clangd

luals() {
    local ver=3.15.0 dir=$PKGS/luals
    if dirty $ver $dir; then
        rm -rf $dir
        mkdir $dir
        curl -L https://github.com/LuaLS/lua-language-server/releases/download/${ver}/lua-language-server-${ver}-${ARCH5}.tar.gz \
            | tar xzf - -C $dir
        undirty $ver $dir
    fi
}
luals

roslyn-ls() {
    local ver=2.93.22 dir=$PKGS/roslyn-ls
    if dirty $ver $dir; then
        rm -rf $dir

        rm -rf $TEMP/roslyn || true
        git clone https://github.com/dotnet/roslyn $TEMP/roslyn \
            --depth 1 --branch VSCode-CSharp-$ver

        pushd $TEMP/roslyn/src/LanguageServer/Microsoft.CodeAnalysis.LanguageServer
        dotnet publish -c Release -o $dir \
            -p:UseAppHost=true \
            -p:IncludeSymbols=false \
            -p:DebugType=None \
            -p:EnableWindowsTargeting=false
        mkdir -p $dir/bin
        ln -sfr $dir/Microsoft.CodeAnalysis.LanguageServer $dir/bin/
        popd

        undirty $ver $dir
    fi
}
roslyn-ls


netcoredbg() {
    if $LINUX; then
        local ver=3.1.2-1054 dir=$PKGS/netcoredbg
        if dirty $ver $dir; then
            rm -rf $dir
            curl -L https://github.com/Samsung/netcoredbg/archive/refs/tags/${ver}.tar.gz \
                | tar xzf - -C $TEMP

            local build=$TEMP/netcoredbg-build
            cmake -S $TEMP/netcoredbg-$ver -B $build \
                -DCMAKE_C_COMPILER=clang \
                -DCMAKE_CXX_COMPILER=clang++ \
                -DCMAKE_INSTALL_PREFIX=$dir

            cmake --build $build -j
            cmake --install $build

            mkdir $dir/bin
            ln -sfr $dir/netcoredbg $dir/bin/

            undirty $ver $dir
        fi
    fi
}
netcoredbg

ripgrep() {
    local ver=15.1.0 dir=$PKGS/ripgrep
    if dirty $ver $dir; then
        mkdir -p $dir/bin
        curl -L https://github.com/BurntSushi/ripgrep/releases/download/${ver}/ripgrep-${ver}-${ARCH1}.tar.gz \
            | tar xzf - -C $TEMP
        cp $TEMP/ripgrep-${ver}-${ARCH1}/rg $dir/bin
        undirty $ver $dir
    fi
}
ripgrep

fd() {
    local ver=10.3.0 dir=$PKGS/fd
    if dirty $ver $dir; then
        mkdir -p $dir/bin
        curl -L https://github.com/sharkdp/fd/releases/download/v${ver}/fd-v${ver}-${ARCH1}.tar.gz \
            | tar xzf - -C $TEMP
        cp $TEMP/fd-v${ver}-${ARCH1}/fd $dir/bin
        undirty $ver $dir
    fi
}
fd

sd() {
    local ver=1.0.0 dir=$PKGS/sd

    if dirty $ver $dir; then
        mkdir -p $dir/bin
        curl -L https://github.com/chmln/sd/releases/download/v${ver}/sd-v${ver}-${ARCH1}.tar.gz \
            | tar xzf - -C $TEMP
        cp $TEMP/sd-v${ver}-${ARCH1}/sd $dir/bin
        undirty $ver $dir
    fi
}
sd

rm -rf $TEMP

#------ Links ------------------------------------------------------------------------------------------------

echo -e "\nSymlinking packages..."

for dir in {bin,lib}; do
    rm -rf $ROOT/$dir && mkdir $ROOT/$dir
    for pkg in $PKGS/*; do
        if [ -d $pkg/$dir ]; then
            ln -sfr $pkg/$dir/* $ROOT/$dir/
        fi
    done
done

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

touch ~/.ssh/config

install tmux.conf tmux/tmux.conf
install gitconfig git/config
install gitignore git/ignore
install nvim/init.lua nvim/init.lua
install nvim/lib.lua nvim/lua/lib.lua
install nvim/setup.lua nvim/lua/setup.lua
install nvim/framework.lua nvim/lua/framework.lua
install fish.fish fish/config.fish
install fish_selini.fish fish/conf.d/selini.fish
install direnv.toml direnv.toml
install starship.toml starship.toml

if $MACOS; then
    install keymap.plist ~/Library/LaunchAgents/keymap.plist
    install fish_macos.fish fish/conf.d/macos.fish
    install ghostty.conf ghostty/config
    install neovide.toml neovide/config.toml
    install aerospace.toml aerospace/aerospace.toml
    install ssh_selini ~/.ssh/config
fi



#------ Reload -----------------------------------------------------------------------------------------------

if $MACOS; then
    launchctl unload ~/Library/LaunchAgents/keymap.plist &>/dev/null || true
    launchctl load ~/Library/LaunchAgents/keymap.plist
fi

echo -e "\n✅ Dots installed!"
