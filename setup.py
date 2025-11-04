#!/usr/bin/env python3

import os, platform, subprocess, shutil, stat
from pathlib import Path
from graphlib import TopologicalSorter

#------ Environment ------------------------------------------------------------------------------------------

ROOT = Path(__file__).resolve().parent
PREFIX = ROOT/'prefix'
PKGS = PREFIX/'pkgs'
WORK = PREFIX/'work'

PREFIX.mkdir(parents=True, exist_ok=True)

sys  = platform.system().lower()  # linux  | darwin
arch = platform.machine().lower() # x86_64 | arm64
host = os.uname().nodename        # navi
triple = {
    ('x86_64','linux'): 'x86_64-unknown-linux-gnu',
    ('arm64','darwin'): 'aarch64-apple-darwin',
}[(arch, sys)]

print('Probing environment...')
print(f'  Host: {host}')
print(f'  System: {sys}-{arch}')

#------ Primitives -------------------------------------------------------------------------------------------

def sh(c: str, cwd: Path = None):
    subprocess.run(['bash', '-euo', 'pipefail', '-c', c], check=True, cwd=cwd)

PLAN = {}
DEPS = {}
def pkg(*, deps=set()):
    def decorator(fn):
        name = fn.__name__
        def plan(v, *args, **kwargs):
            def build():
                d = PKGS/name
                marker = d/'version'
                if not marker.exists() or marker.read_text().strip() != v:
                    print(f'\n================ BUILDING {name} {v} ================')
                    sh(f'rm -rf {d} && mkdir {d}')
                    fn(d, v, *args, **kwargs)
                    marker.write_text(v)

            print(f'  {name} {v}')
            DEPS[name] = deps
            PLAN[name] = build

        return plan
    return decorator

#------ Helpers ----------------------------------------------------------------------------------------------

def extract(url: str, dest: Path):
    dest.mkdir(parents=True, exist_ok=True)
    if   url.endswith(('.tar.gz','.tgz')): sh(f'curl -L {url} | tar xzf - -C {dest}')
    elif url.endswith('.tar.xz'):          sh(f'curl -L {url} | tar xJf - -C {dest}')
    elif url.endswith('.zip'):
        zip = dest/'temp.zip'
        sh(f'curl -L {url} -o {zip} && unzip -q {zip} -d {dest} && rm -f {zip}')
    else: raise ValueError(f'unknown archive format: {url}')

def install(exe: Path, d: Path):
    sh(f'mkdir -p {d}/bin')
    sh(f'chmod +x {exe}')
    sh(f'mv {exe} {d}/bin/')

def build_autotools(src: Path, prefix: Path, *args):
    sh(f'./configure --prefix={prefix} {" ".join(args)}', cwd=src)
    sh(f'make -j && make install', cwd=src)

def build_cmake(src: Path, prefix: Path, *args, j: int = None, targets: list[str] = []):
    components = targets
    targets = ' '.join(f'--target {t}' for t in targets)
    cmake = PKGS/'cmake'/'bin'/'cmake'
    build = WORK/f'{prefix.name}-build'
    sh(f'{cmake} -S {src} -B {build} -DCMAKE_INSTALL_PREFIX={prefix} -DCMAKE_BUILD_TYPE=Release {" ".join(args)}')
    sh(f'{cmake} --build {build} {targets} -j{j or ""}')
    if len(components) == 0:
        sh(f'{cmake} --install {build}')
    else:
        for c in components:
            sh(f'{cmake} --install {build} --component {c}')

def build_cargo(d: Path, v: str, crate: str):
    rust = PKGS/'rust'
    cargo = f'RUSTUP_HOME={rust}/rustup CARGO_HOME={rust} PATH="{rust}/bin:$PATH" cargo'
    sh(f'{cargo} install {crate}@{v} --locked --root {d}')


#------ Toolchains -------------------------------------------------------------------------------------------

@pkg()
def cmake(d: Path, v: str):
    tag = {('darwin','arm64'):'macos-universal', ('linux','x86_64'):'linux-x86_64'}[(sys, arch)]
    extract(f'https://github.com/Kitware/CMake/releases/download/v{v}/cmake-{v}-{tag}.tar.gz', WORK)
    if sys=='darwin':
        sh(f'mv {WORK}/cmake-{v}-{tag}/CMake.app/Contents/{{bin,share}} {d}')
    else:
        sh(f'mv {WORK}/cmake-{v}-{tag}/{{bin,share}} {d}')
    sh(f'rm -f {d}/bin/cmake-gui')

@pkg()
def python(d: Path, v: str):
    extract(f'https://www.python.org/ftp/python/{v}/Python-{v}.tgz', WORK)
    build_autotools(WORK/f'Python-{v}', d, '--disable-test-modules')

@pkg(deps={'python'})
def clang(d: Path, v: str):
    extract(f"https://github.com/llvm/llvm-project/releases/download/llvmorg-{v}/llvm-project-{v}.src.tar.xz", WORK)
    build_cmake(
        WORK/f'llvm-project-{v}.src/llvm', d,
        '-DLLVM_ENABLE_PROJECTS="lld;clang;clang-tools-extra"',
        '-DLLVM_TARGETS_TO_BUILD="X86;AArch64"',
        '-DLLVM_ENABLE_LLD=OFF',
        '-DLLVM_INCLUDE_EXAMPLES=OFF',
        '-DLLVM_INCLUDE_TESTS=OFF',
        j=32,
        targets=['lld', 'clang', 'clang-resource-headers', 'clangd'],
    )

@pkg()
def rust(d: Path, v: str):
    vars = f'RUSTUP_HOME={d}/rustup CARGO_HOME={d}'
    sh(f'curl -L https://static.rust-lang.org/rustup/dist/{triple}/rustup-init -o {WORK}/rustup-init')
    sh(f'chmod +x {WORK}/rustup-init')
    sh(f'RUSTUP_HOME={d}/rustup CARGO_HOME={d} {WORK}/rustup-init --default-toolchain {v} --no-modify-path -y')
    sh(f'{vars} {WORK}/rustup-init --default-toolchain {v} --no-modify-path -y')
    sh(f'{vars} PATH="{d}/bin:$PATH" rustup component remove rust-docs')

@pkg(deps={'cmake'})
def fish(d: Path, v: str):
    extract(f'https://github.com/fish-shell/fish-shell/releases/download/{v}/fish-{v}.tar.xz', WORK)
    build_cmake(WORK/f'fish-{v}', d)

@pkg(deps={'cmake'})
def libevent(d: Path, v: str):
    extract(f'https://github.com/libevent/libevent/releases/download/release-{v}/libevent-{v}.tar.gz', WORK)
    build_cmake(WORK/f'libevent-{v}', d)
    sh(f'rm -rf {d}/bin')

@pkg(deps={'cmake'})
def libutf8proc(d: Path, v: str):
    extract(f'https://github.com/JuliaStrings/utf8proc/archive/refs/tags/v{v}.tar.gz', WORK)
    build_cmake(WORK/f'utf8proc-{v}', d)

@pkg(deps={'cmake', 'libevent', 'libutf8proc'})
def tmux(d: Path, v: str):
    flags = ''
    if sys == 'darwin':
        flags = f'PKG_CONFIG_PATH={PKGS}/libutf8proc/lib/pkgconfig --enable-utf8proc' if sys == 'darwin' else ''

    extract(f'https://github.com/tmux/tmux/releases/download/{v}/tmux-{v}.tar.gz', WORK)
    build_autotools(
        WORK/f'tmux-{v}', d,
        f'CFLAGS="-I{PKGS}/libevent/include" LDFLAGS="-L{PKGS}/libevent/lib"',
        flags,
    )

@pkg()
def nvim(d: Path, v: str):
    tag = {('linux','x86_64'):'linux-x86_64', ('darwin','arm64'):'macos-arm64'}[(sys, arch)]
    extract(f"https://github.com/neovim/neovim/releases/download/v{v}/nvim-{tag}.tar.gz", WORK)
    sh(f'mv {WORK}/nvim-{tag}/* {d}')

@pkg()
def codex(d: Path, v: str):
    tag = triple.replace('gnu', 'musl')
    extract(f'https://github.com/openai/codex/releases/download/rust-v{v}/codex-{tag}.tar.gz', WORK)
    install(WORK/f'codex-{tag}', d)
    sh(f'mv {d}/bin/codex-{tag} {d}/bin/codex')

@pkg()
def lua_ls(d: Path, v: str):
    tag = {('linux','x86_64'):'linux-x64', ('darwin','arm64'):'darwin-arm64'}[(sys, arch)]
    extract(f'https://github.com/LuaLS/lua-language-server/releases/download/{v}/lua-language-server-{v}-{tag}.tar.gz', d/'lua_ls')
    sh(f'mkdir {d}/bin && ln -sfr {d}/lua_ls/bin/lua-language-server {d}/bin/')

@pkg()
def starship(d: Path, v: str):
    extract(f'https://github.com/starship/starship/releases/download/v{v}/starship-{triple}.tar.gz', WORK)
    install(WORK/'starship', d)

@pkg()
def zoxide(d: Path, v: str):
    tag = triple.replace('gnu', 'musl')
    extract(f'https://github.com/ajeetdsouza/zoxide/releases/download/v{v}/zoxide-{v}-{tag}.tar.gz', WORK/'zoxide')
    install(f'{WORK}/zoxide/zoxide', d)

@pkg()
def direnv(d: Path, v: str):
    tag = {('linux','x86_64'):'linux-amd64', ('darwin','arm64'):'darwin-arm64',}[(sys, arch)]
    sh(f'curl -L https://github.com/direnv/direnv/releases/download/v{v}/direnv.{tag} -o {WORK}/direnv')
    install(WORK/'direnv', d)

@pkg(deps={'rust'})
def eza(d: Path, v: str):
    build_cargo(d, v, 'eza')

@pkg()
def ripgrep(d: Path, v: str):
    tag = triple.replace('gnu', 'musl')
    extract(f'https://github.com/BurntSushi/ripgrep/releases/download/{v}/ripgrep-{v}-{tag}.tar.gz', WORK)
    install(WORK/f'ripgrep-{v}-{tag}/rg', d)

@pkg()
def fd(d: Path, v: str):
    extract(f'https://github.com/sharkdp/fd/releases/download/v{v}/fd-v{v}-{triple}.tar.gz', WORK)
    install(WORK/f'fd-v{v}-{triple}/fd', d)

@pkg()
def sd(d: Path, v: str):
    extract(f'https://github.com/chmln/sd/releases/download/v{v}/sd-v{v}-{triple}.tar.gz', WORK)
    install(WORK/f'sd-v{v}-{triple}/sd', d)

@pkg()
def dua(d: Path, v: str):
    build_cargo(d, v, 'dua-cli')

# --- run ----------------------------------------------------------------------------------------------------
if __name__ == '__main__':
    print('\nAdding packages: base')

    # Toolchains
    python('3.14.0')
    if sys=='linux': clang('21.1.0')
    cmake('3.31.9')
    rust('nightly')

    # Libs
    # Tmux
    libevent('2.1.12-stable')
    if sys == 'darwin': libutf8proc('2.11.0')

    # Shell
    tmux('3.5a')
    fish('4.1.2')
    starship('1.24.0')
    zoxide('0.9.8')
    direnv('2.37.1')
    # Tools
    ripgrep('15.1.0')
    eza('0.23.4')
    fd('10.3.0')
    sd('1.0.0')
    dua('2.32.2')

    # Coding
    nvim('0.11.4')
    # Lua
    lua_ls('3.15.0')
    # AI
    codex('0.52.0')

    # Load extensions
    ext = ROOT/'setup.d'
    if ext.is_dir():
        for py in sorted(ext.glob('*.py')):
            print(f"\nAdding packages: {py.name}")
            exec(compile(py.read_text(), str(py), 'exec'), globals(), globals())

    # Build
    print(f'\nProcessing {len(PLAN)} pkgs...')
    PKGS.mkdir(exist_ok=True)
    WORK.mkdir(exist_ok=True)
    graph = {pkg: DEPS.get(pkg) for pkg in PLAN}
    for pkg in TopologicalSorter(graph).static_order():
        if pkg in PLAN:
            PLAN[pkg]()

    print('Creating prefix...')
    # Binaries
    for dir in ['bin', 'lib']:
        dst = PREFIX/dir
        sh(f'rm -rf {dst} && mkdir {dst}')
        for pkg in sorted(PKGS.iterdir()):
            src = pkg/dir
            if src.is_dir():
                sh(f'ln -sfr {src}/* {dst}/')
    # Config
    def conf(src: Path, dst: Path = None):
        sh(f'mkdir -p $(dirname {PREFIX}/config/{dst or src})')
        sh(f'ln -sfr {ROOT}/config/{src} {PREFIX}/config/{dst or src}')

    sh(f'rm -rf {PREFIX}/config && mkdir {PREFIX}/config')
    conf('git')
    conf('tmux.conf', 'tmux/tmux.conf')
    conf('nvim')
    conf('fish/config.fish')
    conf('direnv.toml')
    conf('starship.toml')
    if sys == 'darwin':
        conf('fish/conf.d/macos.fish')
        conf('ghostty.conf', 'ghostty/config')
        conf('neovide.toml', 'neovide/config.toml')
        conf('aerospace.toml', 'aerospace/aerospace.toml')
    sh(f'ln -s ~/.config/* {PREFIX}/config/ 2>/dev/null || true')

    print('Cleaning up...')
    sh(f'rm -rf {WORK}/*')

    # conf('keymap.plist', '~/Library/LaunchAgents/keymap.plist')

    # heads up: ssh + launchagents ignore XDG. keep any ~/.ssh/config or ~/Library/LaunchAgents you need.
    print('\n✅ Done')
