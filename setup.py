#!/usr/bin/env python3

import argparse, os, platform, subprocess, shutil, stat, fnmatch
from pathlib import Path

#------ Environment ------------------------------------------------------------------------------------------

cli = argparse.ArgumentParser()
cli.add_argument('--roles', default='')
cli.add_argument('--prefix', type=Path)
cli = cli.parse_args()

ROOT = Path(__file__).resolve().parent
PREFIX = ROOT/'prefix'
PKGS = PREFIX/'pkgs'
WORK = PREFIX/'work'
CACHE = PREFIX/'cache'

DEST = cli.prefix.resolve() if cli.prefix else ROOT
OUT = DEST/'prefix'

PREFIX.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)

sys  = platform.system().lower()  # linux  | darwin
arch = platform.machine().lower() # x86_64 | arm64
cpus = str(os.cpu_count() or 1)
triple = {
    ('x86_64','linux'): 'x86_64-unknown-linux-gnu',
    ('arm64','darwin'): 'aarch64-apple-darwin',
}[(arch, sys)]

def host(*patterns): return any(fnmatch.fnmatch(os.uname().nodename.lower(), p.lower()) for p in patterns)
def role(*names): return any(n.lower() in ROLES for n in names)

ROLES = {r.strip().lower() for r in cli.roles.split(',') if r.strip()}
if not ROLES:
    if   host('dsk-nyc-linux-01'):     ROLES = {'selini', 'dev', 'desktop'}
    elif host('mtl-fit-c-03'):         ROLES = {'selini', 'dev'}
    elif host('ta-tky-*', 'ac-hkg-*'): ROLES = {'selini'}

print('Probing environment...')
print(f'  Host: {os.uname().nodename.lower()}')
print(f'  Roles: {" ".join(sorted(ROLES)) or "-"}')
print(f'  System: {sys}-{arch}')
print(f'  CPUs: {cpus}')
if DEST != ROOT: print(f'  Dest: {DEST}')

#------ Primitives -------------------------------------------------------------------------------------------

def sh(c: str, cwd: Path = None):
    subprocess.run(['bash', '--noprofile', '--norc', '-euo', 'pipefail', '-c', c], check=True, cwd=cwd)

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
    elif url.endswith('.bz2'):             sh(f'curl -L {url} | tar xjf - -C {dest}')
    elif url.endswith('.zip'):
        zip = dest/'temp.zip'
        sh(f'curl -L {url} -o {zip} && unzip -q {zip} -d {dest} && rm -f {zip}')
    else: raise ValueError(f'unknown archive format: {url}')

def install(exe: Path, d: Path, *, rename: str | None = None):
    sh(f'mkdir -p {d}/bin')
    sh(f'chmod +x {exe}')
    sh(f'mv {exe} {d}/bin/{rename or exe}')

def lnr(src, dst):
    """Relative symlinks into dst. src may be a shell glob. Both must share a common parent."""
    sh(f'cd {dst} && for f in {src}; do ln -sf "../${{f#{dst.parent}/}}" .; done')

def build_autotools(src: Path, prefix: Path, *args, env: str = '', use_clang: bool = False):
    clang = PKGS/'clang/bin/clang'
    clang = f'CC={clang} CXX={clang}++' if use_clang else ''

    sh(f'{env} ./configure --prefix={prefix} {clang} {" ".join(args)}', cwd=src)
    sh(f'{env} make -j{cpus} && {env} make install', cwd=src)

def build_automake(src: Path, prefix: Path, *args, env: str = ''):
    automake = PKGS/'automake'
    sh(f'{env} PATH="{automake}/bin:$PATH" autoreconf --install', cwd=src)
    build_autotools(src, prefix, *args)

def build_cmake(src: Path, prefix: Path, *args, use_clang: bool = False, targets: list = [], env: str = ''):
    components = targets
    targets = ' '.join(f'--target {t}' for t in targets)
    clang = PKGS/'clang/bin/clang'
    cmake = PKGS/'cmake/bin/cmake'
    compiler = f'-DCMAKE_C_COMPILER={clang} -DCMAKE_CXX_COMPILER={clang}++' if use_clang else ''
    build = WORK/f'{prefix.name}-build'
    sh(f'{env} {cmake} -S {src} -B {build} {compiler} -DCMAKE_INSTALL_PREFIX={prefix} -DCMAKE_BUILD_TYPE=Release {" ".join(args)}')
    sh(f'{env} {cmake} --build {build} {targets} -j{cpus}')
    if len(components) == 0:
        sh(f'{cmake} --install {build}')
    else:
        for c in components:
            sh(f'{cmake} --install {build} --component {c}')

def build_meson(src: Path, prefix: Path, *args, env: str = ''):
    clang = PKGS/'clang/bin/clang'
    meson = f'PYTHONPATH="{PKGS}/meson/lib/python3.14/site-packages" {PKGS}/meson/bin/meson'
    ninja = PKGS/'ninja'
    sh(f'{env} PATH="{ninja}/bin:$PATH" CC={clang} CXX={clang}++ CC_LD=lld CXX_LD=lld {meson} setup build --prefix={prefix} {" ".join(args)}', cwd=src)
    sh(f'{meson} compile -C build', cwd=src)
    sh(f'{meson} install -C build', cwd=src)

def build_cargo(d: Path, v: str, crate: str, git: str = None, features: list = []):
    rust = PKGS/'rust'
    cargo = f'RUSTUP_HOME={rust}/rustup CARGO_HOME={CACHE}/cargo PATH="{rust}/bin:$PATH" cargo'
    src = f'--git {git} --tag {v}' if git else f'{crate}@{v}'
    features = f'--no-default-features --features {",".join(features)}' if features else ''
    sh(f'{cargo} install {src} {features} --locked --root {d}')


def build_pip(d: Path, v: str, package: str):
    pip = PKGS/'python/bin/pip3'
    sh(f'{pip} install {package}=={v} --prefix={d} --ignore-installed')

def build_npm(d: Path, v: str, package: str):
    node = PKGS/'node'
    sh(f'PATH="{node}/bin:$PATH" npm install -g --prefix={d} {package}@{v}')

#------ Toolchains -------------------------------------------------------------------------------------------

@pkg()
def m4(d: Path, v: str):
    extract(f'https://ftp.gnu.org/gnu/m4/m4-{v}.tar.xz', WORK)
    build_autotools(WORK/f'm4-{v}', d)

@pkg(deps={'m4'})
def bison(d: Path, v: str):
    m4 = PKGS/'m4'
    extract(f'https://ftp.gnu.org/gnu/bison/bison-{v}.tar.xz', WORK)
    build_autotools(WORK/f'bison-{v}', d, env=f'PATH="{m4}/bin:$PATH"')

@pkg(deps={'m4'})
def flex(d: Path, v: str):
    m4 = PKGS/'m4'
    extract(f'https://github.com/westes/flex/releases/download/v{v}/flex-{v}.tar.gz', WORK)
    build_autotools(WORK/f'flex-{v}', d, env=f'PATH="{m4}/bin:$PATH"')

@pkg()
def pkgconf(d: Path, v: str):
    extract(f'https://distfiles.dereferenced.org/pkgconf/pkgconf-{v}.tar.xz', WORK)
    build_autotools(WORK/f'pkgconf-{v}', d)
    sh(f'ln -sf pkgconf {d}/bin/pkg-config')

@pkg()
def ninja(d: Path, v: str):
    platform = {('linux','x86_64'):'linux', ('darwin','arm64'):'mac'}[(sys, arch)]
    extract(f'https://github.com/ninja-build/ninja/releases/download/v{v}/ninja-{platform}.zip', WORK)
    install(WORK/'ninja', d)

@pkg(deps={'m4'})
def automake(d: Path, v: str):
    m4 = PKGS/'m4'
    vars = f'PATH="{d}/bin:{m4}/bin:$PATH"'

    libtool_v = '2.5.4'
    extract(f'https://mirror.us-midwest-1.nexcess.net/gnu/libtool/libtool-{libtool_v}.tar.xz', WORK)
    build_autotools(WORK/f'libtool-{libtool_v}', d, vars)

    autoconf_v = '2.72'
    extract(f'https://ftp.gnu.org/gnu/autoconf/autoconf-{autoconf_v}.tar.xz', WORK)
    build_autotools(WORK/f'autoconf-{autoconf_v}', d, vars)

    extract(f'https://ftp.gnu.org/gnu/automake/automake-{v}.tar.xz', WORK)
    build_autotools(WORK/f'automake-{v}', d, vars)

@pkg()
def cmake(d: Path, v: str):
    tag = {('linux','x86_64'):'linux-x86_64', ('darwin','arm64'):'macos-universal'}[(sys, arch)]
    extract(f'https://github.com/Kitware/CMake/releases/download/v{v}/cmake-{v}-{tag}.tar.gz', WORK)
    if sys=='darwin':
        sh(f'mv {WORK}/cmake-{v}-{tag}/CMake.app/Contents/{{bin,share}} {d}')
    else:
        sh(f'mv {WORK}/cmake-{v}-{tag}/{{bin,share}} {d}')
    sh(f'rm -f {d}/bin/cmake-gui')

@pkg()
def openssl(d: Path, v: str):
    extract(f'https://github.com/openssl/openssl/releases/download/openssl-{v}/openssl-{v}.tar.gz', WORK)
    sh(f'./config --prefix={d} --openssldir={d}/ssl', cwd=WORK/f'openssl-{v}')
    sh(f'make -j{cpus} && make install_sw', cwd=WORK/f'openssl-{v}')

@pkg()
def sqlite(d: Path, v: str):
    extract(f'https://www.sqlite.org/2025/sqlite-autoconf-{v}.tar.gz', WORK)
    build_autotools(WORK/f'sqlite-autoconf-{v}', d)

@pkg(deps={'sqlite', 'openssl', 'pkgconf'})
def python(d: Path, v: str):
    sqlite = PKGS/'sqlite/lib'
    openssl_dir = PKGS/'openssl'
    pkg_config_path = f'{openssl_dir}/lib/pkgconfig:{sqlite}/pkgconfig'
    pkg_config = f'{PKGS}/pkgconf/bin/pkgconf'
    extract(f'https://www.python.org/ftp/python/{v}/Python-{v}.tgz', WORK)
    build_autotools(WORK/f'Python-{v}', d, '--disable-test-modules',
        f'--with-openssl={openssl_dir}', '--with-openssl-rpath=auto',
        f'PKG_CONFIG="{pkg_config}"', f'PKG_CONFIG_PATH="{pkg_config_path}"',
        env=f'LD_LIBRARY_PATH="{sqlite}"')

@pkg(deps={'python', 'cmake'})
def clang(d: Path, v: str):
    extract(f"https://github.com/llvm/llvm-project/releases/download/llvmorg-{v}/llvm-project-{v}.src.tar.xz", WORK)
    build_cmake(
        WORK/f'llvm-project-{v}.src/llvm', d,
        '-DLLVM_ENABLE_PROJECTS="lld;clang;clang-tools-extra"',
        #'-DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind"',
        '-DLLVM_TARGETS_TO_BUILD="X86;AArch64;AMDGPU"',
        '-DLLVM_ENABLE_LLD=OFF',
        '-DLLVM_INCLUDE_EXAMPLES=OFF',
        '-DLLVM_INCLUDE_TESTS=OFF',
        use_clang=False,
        targets=['lld', 'clang', 'llvm-ar', 'llvm-ranlib', 'clang-resource-headers', 'clangd'],
        #targets=['lld', 'clang', 'llvm-ar', 'llvm-ranlib', 'clang-resource-headers', 'clangd', 'runtimes'],
    )

@pkg(deps={'python'})
def meson(d: Path, v: str):
    build_pip(d, v, 'meson')

@pkg()
def rust(d: Path, v: str):
    vars = f'RUSTUP_HOME={d}/rustup CARGO_HOME={CACHE}/cargo'
    sh(f'curl -L https://static.rust-lang.org/rustup/dist/{triple}/rustup-init -o {WORK}/rustup-init')
    sh(f'chmod +x {WORK}/rustup-init')
    sh(f'{vars} {WORK}/rustup-init --default-toolchain {v} --component rust-analyzer --no-modify-path -y')
    sh(f'{vars} {WORK}/rustup-init --default-toolchain {v} --no-modify-path -y')
    sh(f'{vars} PATH="{d}/bin:$PATH" rustup component remove rust-docs')
    sh(f'rm -rf {d}/rustup/toolchains/*/share/{{doc,man}}')

@pkg()
def node(d: Path, v: str):
    tag = {('linux','x86_64'):'linux-x64', ('darwin','arm64'):'darwin-arm64'}[(sys, arch)]
    extract(f'https://nodejs.org/dist/v{v}/node-v{v}-{tag}.tar.xz', WORK)
    sh(f'mv {WORK}/node-v{v}-{tag}/* {d}')
    sh(f'rm -rf {d}/share/man')

@pkg()
def zig(d: Path, v: str):
    tag = {('linux','x86_64'):'x86_64-linux', ('darwin','arm64'):'aarch64-macos'}[(sys, arch)]
    extract(f'https://ziglang.org/download/{v}/zig-{tag}-{v}.tar.xz', WORK)
    sh(f'mv {WORK}/zig-{tag}-{v} {d}/zig')
    sh(f'mkdir -p {d}/bin && ln -sf ../zig/zig {d}/bin/zig')

@pkg(deps={'cmake', 'rust'})
def fish(d: Path, v: str):
    rust = PKGS/'rust'
    vars = f'PATH="{rust}/bin:$PATH" RUSTUP_HOME={rust}/rustup CARGO_HOME={CACHE}/cargo'

    extract(f'https://github.com/fish-shell/fish-shell/releases/download/{v}/fish-{v}.tar.xz', WORK)
    build_cmake(WORK/f'fish-{v}', d, env=vars)
    sh(f'rm -rf {d}/share/man {d}/share/fish/man {d}/share/doc')

@pkg(deps={'cmake'})
def libevent(d: Path, v: str):
    extract(f'https://github.com/libevent/libevent/releases/download/release-{v}/libevent-{v}.tar.gz', WORK)
    build_cmake(WORK/f'libevent-{v}', d)
    sh(f'rm -rf {d}/bin')

@pkg(deps={'cmake'})
def libutf8proc(d: Path, v: str):
    extract(f'https://github.com/JuliaStrings/utf8proc/archive/refs/tags/v{v}.tar.gz', WORK)
    build_cmake(WORK/f'utf8proc-{v}', d)

@pkg()
def ncurses(d: Path, v: str):
    extract(f'https://invisible-island.net/archives/ncurses/ncurses-{v}.tar.gz', WORK)
    build_autotools(WORK/f'ncurses-{v}', d, '--with-shared', '--without-debug', '--enable-widec', '--enable-pc-files',
        '--with-versioned-syms', f'--with-pkg-config-libdir={d}/lib/pkgconfig')
    sh(f'rm -rf {d}/bin {d}/share/man')
    keep = ' '.join(f'! -name {t}' for t in ['linux', 'xterm-256color', 'alacritty', 'tmux-256color'])
    sh(f'find {d}/share/terminfo \\( -type f -o -type l \\) {keep} -delete')
    sh(f'find {d}/share/terminfo -type d -empty -delete')

@pkg(deps={'ncurses'})
def readline(d: Path, v: str):
    ncurses = PKGS/'ncurses'
    extract(f'https://ftp.gnu.org/gnu/readline/readline-{v}.tar.gz', WORK)
    build_autotools(WORK/f'readline-{v}', d,
        '--with-curses', '--with-shared-termcap-library', '--enable-multibyte',
        f'CPPFLAGS=-I{ncurses}/include', f'LDFLAGS=-L{ncurses}/lib',
        env='bash_cv_termcap_lib=libncursesw')

@pkg(deps={'cmake', 'pkgconf', 'bison', 'libevent', 'libutf8proc', 'ncurses'})
def tmux(d: Path, v: str):
    bison = PKGS/'bison'
    ncurses = PKGS/'ncurses/lib/pkgconfig'
    libevent = PKGS/'libevent/lib/pkgconfig'
    pkg_config_path = f'{ncurses}:{libevent}'

    flags = ''
    if sys == 'darwin':
        flags = f'--enable-utf8proc'
        pkg_config_path += f':{PKGS}/libutf8proc/lib/pkgconfig'

    extract(f'https://github.com/tmux/tmux/releases/download/{v}/tmux-{v}.tar.gz', WORK)
    build_autotools(
        WORK/f'tmux-{v}', d,
        f'PATH="{bison}/bin:$PATH"',
        f'PKG_CONFIG="{PKGS}/pkgconf/bin/pkgconf"',
        f'PKG_CONFIG_PATH="{pkg_config_path}"',
        flags,
    )

@pkg()
def nvim(d: Path, v: str):
    tag = {('linux','x86_64'):'linux-x86_64', ('darwin','arm64'):'macos-arm64'}[(sys, arch)]
    extract(f"https://github.com/neovim/neovim/releases/download/v{v}/nvim-{tag}.tar.gz", WORK)
    sh(f'mv {WORK}/nvim-{tag}/* {d}')

@pkg()
def uv(d: Path, v: str):
    extract(f'https://github.com/astral-sh/uv/releases/download/{v}/uv-{triple}.tar.gz', WORK)
    sh(f'mkdir -p {d}/bin')
    sh(f'mv {WORK}/uv-{triple}/uv {WORK}/uv-{triple}/uvx {d}/bin/')

# See https://github.com/openai/codex/releases
@pkg()
def codex(d: Path, v: str):
    tag = triple.replace('gnu', 'musl')
    extract(f'https://github.com/openai/codex/releases/download/rust-v{v}/codex-{tag}.tar.gz', WORK)
    extract(f'https://github.com/openai/codex/releases/download/rust-v{v}/codex-code-mode-host-{tag}.tar.gz', WORK)
    install(WORK/f'codex-{tag}', d, rename='codex')
    install(WORK/f'codex-code-mode-host-{tag}', d, rename='codex-code-mode-host')

# Get latest version with `curl -L https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/latest` or stable
# See https://claude.ai/install.sh 
@pkg()
def claude(d: Path, v: str):
    tag = {('linux','x86_64'):'linux-x64', ('darwin','arm64'):'darwin-arm64'}[(sys, arch)]
    dest = d/'bin'
    sh(f'mkdir -p {dest}')
    sh(f'curl -Lo {dest}/claude https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/{v}/{tag}/claude')
    sh(f'chmod +x {dest}/claude')

@pkg()
def sqlcmd(d: Path, v: str):
    tag = {('linux','x86_64'):'linux-amd64', ('darwin','arm64'):'darwin-arm64'}[(sys, arch)]
    sh(f'mkdir -p {d}/bin')
    extract(f'https://github.com/microsoft/go-sqlcmd/releases/download/v{v}/sqlcmd-{tag}.tar.bz2', d/'bin')
    sh(f'rm -f {d}/bin/sqlcmd_debug {d}/bin/NOTICE.md')

@pkg()
def duckdb(d: Path, v: str):
    tag = {('linux','x86_64'):'linux-amd64', ('darwin','arm64'):'osx-universal'}[(sys, arch)]
    sh(f'mkdir {d}/bin')
    extract(f'https://install.duckdb.org/v{v}/duckdb_cli-{tag}.zip', d/'bin')

@pkg()
def lua_ls(d: Path, v: str):
    tag = {('linux','x86_64'):'linux-x64', ('darwin','arm64'):'darwin-arm64'}[(sys, arch)]
    extract(f'https://github.com/LuaLS/lua-language-server/releases/download/{v}/lua-language-server-{v}-{tag}.tar.gz', d/'lua_ls')
    sh(f'mkdir {d}/bin && ln -sf ../lua_ls/bin/lua-language-server {d}/bin/')

@pkg(deps={'bison', 'flex'})
def postgres(d: Path, v: str):
    path = f'PATH="{PKGS}/bison/bin:{PKGS}/flex/bin:$PATH"'
    extract(f'https://ftp.postgresql.org/pub/source/v{v}/postgresql-{v}.tar.bz2', WORK)
    src = WORK/f'postgresql-{v}'
    sh(f'{path} ./configure --prefix={d} --without-icu --without-lz4 --without-zstd --with-openssl', cwd=src)
    for t in ['src/interfaces/libpq', 'src/bin/pg_dump', 'src/bin/psql']:
        sh(f'{path} make -j{cpus} && make install', cwd=src/t)

@pkg(deps={'rust'})
def sqlx_cli(d: Path, v: str):
    # rustls instead of native-tls avoids openssl; sqlite is bundled from source.
    build_cargo(d, v, 'sqlx-cli', features=['rustls', 'postgres', 'sqlite'])

@pkg(deps={'python', 'node'})
def basedpyright(d: Path, v: str):
    build_pip(d, v, 'basedpyright')
    sh(f'rm -rf {d}/share/man')

@pkg(deps={'node'})
def bash_language_server(d: Path, v: str):
    build_npm(d, v, 'bash-language-server')

@pkg(deps={'rust'})
def systemd_lsp(d: Path, v: str):
    build_cargo(d, v, 'systemd-lsp', git='https://github.com/JFryy/systemd-lsp')

@pkg(deps={'python'})
def ykman(d: Path, v: str):
    build_pip(d, v, 'yubikey-manager')

@pkg()
def pixi(d: Path, v: str):
    tag = {('linux','x86_64'):'x86_64-unknown-linux-musl', ('darwin','arm64'):'aarch64-apple-darwin'}[(sys, arch)]
    extract(f'https://github.com/prefix-dev/pixi/releases/download/v{v}/pixi-{tag}.tar.gz', WORK)
    install(WORK/'pixi', d)

@pkg()
def just(d: Path, v: str):
    tag = {('linux','x86_64'):'x86_64-unknown-linux-musl', ('darwin','arm64'):'aarch64-apple-darwin'}[(sys, arch)]
    extract(f'https://github.com/casey/just/releases/download/{v}/just-{v}-{tag}.tar.gz', WORK)
    install(WORK/'just', d)

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
def fzf(d: Path, v: str):
    tag = {('linux','x86_64'):'linux_amd64', ('darwin','arm64'):'darwin_arm64'}[(sys, arch)]
    extract(f'https://github.com/junegunn/fzf/releases/download/v{v}/fzf-{v}-{tag}.tar.gz', WORK)
    install(WORK/'fzf', d)

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

@pkg(deps={'rust'})
def dust(d: Path, v: str):
    build_cargo(d, v, 'du-dust')

@pkg()
def bun(d: Path, v: str):
    tag = {('linux','x86_64'):'linux-x64', ('darwin','arm64'):'darwin-aarch64'}[(sys, arch)]
    extract(f'https://github.com/oven-sh/bun/releases/download/bun-v{v}/bun-{tag}.zip', WORK)
    install(WORK/f'bun-{tag}/bun', d)

@pkg()
def gh(d: Path, v: str):
    tag = {('linux','x86_64'):'linux_amd64', ('darwin','arm64'):'macOS_arm64'}[(sys, arch)]
    ext = 'zip' if sys == 'darwin' else 'tar.gz'
    extract(f'https://github.com/cli/cli/releases/download/v{v}/gh_{v}_{tag}.{ext}', WORK)
    sh(f'mv {WORK}/gh_{v}_{tag}/* {d}/')
    sh(f'rm -rf {d}/share/man')

@pkg()
def git_absorb(d: Path, v: str):
    tag = {('linux','x86_64'):'x86_64-unknown-linux-musl', ('darwin','arm64'):'x86_64-apple-darwin'}[(sys, arch)]
    extract(f'https://github.com/tummychow/git-absorb/releases/download/{v}/git-absorb-{v}-{tag}.tar.gz', WORK)
    install(WORK/f'git-absorb-{v}-{tag}/git-absorb', d)

@pkg()
def shellcheck(d: Path, v: str):
    tag = {('linux','x86_64'):'linux.x86_64', ('darwin','arm64'):'darwin.aarch64'}[(sys, arch)]
    extract(f'https://github.com/koalaman/shellcheck/releases/download/v{v}/shellcheck-v{v}.{tag}.tar.xz', WORK)
    install(WORK/f'shellcheck-v{v}/shellcheck', d)

@pkg(deps={'rust'})
def dua(d: Path, v: str):
    build_cargo(d, v, 'dua-cli')

@pkg(deps={'rust'})
def cargo_watch(d: Path, v: str):
    build_cargo(d, v, 'cargo-watch')

@pkg(deps={'rust'})
def tokei(d: Path, v: str):
    build_cargo(d, v, 'tokei')

@pkg()
def zstd(d: Path, v: str):
    extract(f'https://github.com/facebook/zstd/releases/download/v{v}/zstd-{v}.tar.gz', WORK)
    make = f'make -j{cpus} PREFIX={d}'
    sh(make, cwd=WORK/f'zstd-{v}')
    sh(f'{make} install', cwd=WORK/f'zstd-{v}')

@pkg()
def libxml2(d: Path, v: str):
    vv = '.'.join(v.split('.')[:2]) # 2.15.1 -> 2.15
    extract(f'https://download.gnome.org/sources/libxml2/{vv}/libxml2-{v}.tar.xz', WORK)
    build_autotools(
        WORK/f'libxml2-{v}', d, 
        'CFLAGS="-fPIC"',
        '--without-python --without-docbook --without-icu',
        '--disable-shared --enable-static',
    )

@pkg(deps={'libpcap'})
def wireshark(d: Path, v: str):
    src = WORK/f'wireshark-{v}'
    if not src.exists():
        sh(f'git clone --branch wireshark-{v} --depth 1 git@github.com:Selini-3rdparty/wireshark.git {src}')
    system = '/usr/share/pkgconfig:/usr/lib64/pkgconfig'
    libpcap = PKGS/'libpcap'
    disable = [f'-DBUILD_{tool}=OFF' for tool in [
        'rawshark','sharkd','tfshark', 'text2pcap','randpkt','randpktdump',
        'mmdbresolve','ciscodump','sshdump','wifidump','udpdump',
        'androiddump','dpauxmon','sdjournal','captype'
    ]]
    build_cmake(
        WORK/f'wireshark-{v}', d,
        f'-DCMAKE_C_FLAGS="-I{libpcap}/include" -DCMAKE_EXE_LINKER_FLAGS="-L{libpcap}/lib"',
        '-DENABLE_PLUGINS=OFF',
        '-DENABLE_LUA=OFF',
        '-DENABLE_NETLINK=OFF',
        '-DENABLE_KERBEROS=OFF',
        '-DENABLE_SBC=OFF',
        '-DENABLE_SPANDSP=OFF',
        '-DENABLE_BCG729=OFF',
        '-DENABLE_AMRNB=OFF',
        '-DENABLE_ILBC=OFF',
        '-DENABLE_LIBXML2=OFF',
        '-DENABLE_NGHTTP2=OFF',
        '-DENABLE_NGHTTP3=OFF',
        '-DBUILD_wireshark=OFF',
        '-DBUILD_tshark=ON',
        '-DBUILD_dumpcap=ON',
        *disable,
        env=f'PKG_CONFIG_PATH="{libpcap}/lib/pkgconfig:{system}"',
    )

@pkg(deps={'wireshark'})
def termshark(d: Path, v: str):
    tag = {('linux','x86_64'):'linux_x64', ('darwin','arm64'):'MacOS_arm64',}[(sys, arch)]
    extract(f'https://github.com/gcla/termshark/releases/download/v{v}/termshark_{v}_{tag}.tar.gz', WORK)
    install(WORK/f'termshark_{v}_{tag}/termshark', d)

@pkg(deps={'bison', 'flex'})
def libpcap(d: Path, v: str):
    extract(f'https://www.tcpdump.org/release/libpcap-{v}.tar.xz', WORK)
    build_autotools(WORK/f'libpcap-{v}', d, '--disable-dbus', '--enable-shared', '--enable-static',
        env=f'PATH="{PKGS}/bison/bin:{PKGS}/flex/bin:$PATH"')
    sh(f'rm -rf {d}/share/man')

@pkg()
def netcat(d: Path, v: str):
    extract(f'https://sourceforge.net/projects/netcat/files/netcat/{v}/netcat-{v}.tar.gz', WORK)
    build_autotools(WORK/f'netcat-{v}', d)

@pkg()
def iperf3(d: Path, v: str):
    extract(f'https://github.com/esnet/iperf/releases/download/{v}/iperf-{v}.tar.gz', WORK)
    build_autotools(WORK/f'iperf-{v}', d)

@pkg(deps={'rust'})
def gping(d: Path, v: str):
    build_cargo(d, v, 'gping')

@pkg(deps={'rust'})
def oha(d: Path, v: str):
    build_cargo(d, v, 'oha')

@pkg()
def influx(d: Path, v: str):
    tag = {('linux','x86_64'):'linux-amd64', ('darwin','arm64'):'linux-arm64'}[(sys, arch)]
    extract(f'https://dl.influxdata.com/influxdb/releases/influxdb2-client-{v}-{tag}.tar.gz', WORK)
    install(WORK/'influx', d)

@pkg()
def snitch(d: Path, v: str):
    tag = {('linux','x86_64'):'linux_amd64', ('darwin','arm64'):'darwin_arm64'}[(sys, arch)]
    extract(f'https://github.com/karol-broda/snitch/releases/download/v{v}/snitch_{v}_{tag}.tar.gz', WORK)
    install(WORK/'snitch', d)

@pkg(deps={'rust'})
def alacritty(d: Path, v: str):
    build_cargo(d, v, 'alacritty')

@pkg(deps={'rust'})
def neovide(d: Path, v: str):
    build_cargo(d, v, 'neovide')

@pkg()
def zen(d: Path, v: str):
    extract(f'https://github.com/zen-browser/desktop/releases/download/{v}/zen.linux-x86_64.tar.xz', WORK)
    sh(f'mv {WORK}/zen {d}/')
    sh(f'mkdir -p {d}/bin && ln -sf ../zen/zen {d}/bin/zen')

@pkg()
def dwm(d: Path, v: str):
    extract(f'https://github.com/sln-jack/dwm/archive/refs/heads/master.tar.gz', WORK)
    sh(f'rm -f {WORK}/dwm-master/config.h && make -j{cpus} && DESTDIR={d} make install', cwd=WORK/'dwm-master')

@pkg()
def sshot(d: Path, v: str):
    # WARNING: impure to take host libX11
    sh(f'mkdir -p {d}/bin && cc -O2 -o {d}/bin/sshot {ROOT}/files/sshot.c -lX11 -lXext')

@pkg()
def scast(d: Path, v: str):
    # WARNING: impure to take host libX11
    sh(f'mkdir -p {d}/bin && cc -O2 -o {d}/bin/scast {ROOT}/files/scast.c -lX11 -lXext')

@pkg()
def fonts(d: Path, v: str):
    sh(f'mkdir -p {OUT}/share/fonts && cp {ROOT}/files/*.ttf {OUT}/share/fonts/ && fc-cache -f {OUT}/share/fonts')

@pkg()
def is_interactive_ssh(d: Path, v: str):
    sh(f'mkdir -p {d}/bin && install -m755 {ROOT}/files/is-interactive-ssh {d}/bin/')

@pkg()
def dmenu(d: Path, v: str):
    extract(f'https://github.com/sln-jack/dmenu/archive/refs/heads/master.tar.gz', WORK)
    sh(f'rm -f {WORK}/dmenu-master/config.h && make -j{cpus} && DESTDIR={d} make install', cwd=WORK/'dmenu-master')

# --- run ----------------------------------------------------------------------------------------------------
if __name__ == '__main__':
    print('\nAdding packages: base')

    # Toolchains
    if role('dev'):
        pkgconf('3.0.7')
        ninja('1.13.2')
        m4('1.4.20')
        bison('3.8.2')
        flex('2.6.4')
        automake('1.18.1')
        if sys == 'macos': openssl('3.6.1')
        if sys=='linux': clang('22.1.0')
        cmake('3.31.9')
        meson('1.9.2')
        rust('nightly')
        node('24.12.0')
        bun('1.3.9')
        zig('0.16.0')
        python('3.14.0')
        libxml2('2.15.1')

    # Libs
    sqlite('3510100')
    # Tmux
    ncurses('6.6')
    readline('8.3')
    libevent('2.1.12-stable')
    if sys == 'darwin': libutf8proc('2.11.0')

    # Shell
    tmux('3.5a')
    fish('4.1.2')
    starship('1.24.0')
    zoxide('0.9.8')
    direnv('2.37.1')
    # Tools
    if role('dev'): pixi('0.66.0')
    just('1.46.0')
    fzf('0.68.0')
    ripgrep('15.1.0')
    eza('0.23.4')
    fd('10.3.0')
    sd('1.0.0')
    dust('1.2.4')
    dua('2.32.2')
    zstd('1.5.7')
    gh('2.87.3')
    git_absorb('0.9.0')
    shellcheck('0.11.0')
    is_interactive_ssh('1.0')
    if role('dev'): cargo_watch('8.5.3')
    tokei('15.0.0')
    if role('desktop'): ykman('5.9.1')

    # Coding
    nvim('0.11.4')
    # Lua
    if role('dev'): lua_ls('3.15.0')
    # Python
    if role('dev'): uv('0.11.3')
    if role('dev'): basedpyright('1.39.0')
    # Bash
    if role('dev'): bash_language_server('5.6.0')
    # Systemd
    if role('dev'): systemd_lsp('v2026.08.03')
    # AI
    codex('0.154.0')
    claude('2.1.269')
    # DB
    postgres('18.3')
    sqlx_cli('0.9.0')
    sqlcmd('1.10.0')
    duckdb('1.4.4')
    influx('2.8.0')

    # Networking
    libpcap('1.10.5')
    netcat('0.7.1')
    iperf3('3.21')
    gping('1.20.1')
    oha('1.12.1')
    snitch('0.2.2')

    # Gui
    if role('desktop'):
        fonts('34.8.0-nf3.5.1')
        alacritty('0.16.1')
        neovide('0.15.2')
        zen('1.19.13b')

        # X11 Windowing
        dwm('6.6')
        dmenu('5.4')
        sshot('1.0')
        scast('1.0')

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
    CACHE.mkdir(exist_ok=True)

    # Topo sort
    seen, ordered = set(), []
    def visit(pkg):
        if pkg in seen: return
        seen.add(pkg)
        for dep in DEPS.get(pkg, ()):
            visit(dep)
        ordered.append(pkg)
    for pkg in PLAN:
        visit(pkg)
    # Build
    for pkg in ordered:
        if pkg in PLAN:
            PLAN[pkg]()

    print('Creating prefix...')
    pkgs = OUT/'pkgs'
    if DEST != ROOT:
        print(f'Copying {len(PLAN)} pkgs to {DEST}...')
        sh(f'mkdir -p {pkgs}')
        for p in pkgs.iterdir():
            if p.name not in PLAN: sh(f'rm -rf {p}')
        for pkg in sorted(PLAN):
            sh(f'rm -rf {pkgs}/{pkg} && cp -a {PKGS}/{pkg} {pkgs}/')
        sh(f'rm -rf {DEST}/config && cp -a {ROOT}/config {DEST}/config')
        sh(f'cp -a {ROOT}/activate {ROOT}/deactivate {DEST}/')

    # Binaries
    for dir in ['bin', 'lib']:
        dst = OUT/dir
        sh(f'rm -rf {dst} && mkdir {dst}')
        for pkg in sorted(PLAN):
            src = pkgs/pkg/dir
            if src.is_dir():
                lnr(f'{src}/*', dst)

    # Python site-packages: symlink all package site-packages into prefix/lib/python/site-packages
    dst = OUT/'lib'/'python'/'site-packages'
    dst.mkdir(parents=True, exist_ok=True)
    for pydir in sorted(p for pkg in PLAN for p in (pkgs/pkg).glob('lib/python*/site-packages')):
        for item in pydir.iterdir():
            link = dst/item.name
            if not link.exists():
                link.symlink_to(os.path.relpath(item, dst))

    # Gated on base_prefix so foreign Pythons inheriting PYTHONPATH don't graft.
    (OUT/'lib'/'python'/'sitecustomize.py').write_text(
        'import os, sys, site\n'
        'here = os.path.dirname(__file__)\n'
        'if os.path.realpath(sys.base_prefix) == os.path.realpath(f"{here}/../../pkgs/python"):\n'
        '    site.addsitedir(f"{here}/site-packages")\n'
    )
    # Config
    def conf(src_name, dst_name=None):
        target = DEST/'config'/src_name
        link = OUT/'config'/(dst_name or src_name)
        rel = os.path.relpath(target, link.parent)
        sh(f'mkdir -p {link.parent}')
        sh(f'ln -sf {rel} {link}')

    sh(f'rm -rf {OUT}/config && mkdir {OUT}/config')
    conf('git')
    conf('tmux.conf', 'tmux/tmux.conf')
    conf('nvim')
    conf('fish/config.fish')
    conf('direnv.toml')
    conf('starship.toml')
    conf('alacritty.toml')
    conf('neovide.toml', 'neovide/config.toml')
    conf('podman-storage.conf', 'containers/storage.conf')
    if sys == 'linux':
        conf('fish/linux.fish', 'fish/conf.d/linux.fish')
    if sys == 'darwin':
        conf('fish/macos.fish', 'fish/conf.d/macos.fish')
        conf('ghostty.conf', 'ghostty/config')
        conf('aerospace.toml', 'aerospace/aerospace.toml')
    if DEST == ROOT:
        sh(f'ln -s ~/.config/* {OUT}/config/ 2>/dev/null || true')

    print('Cleaning up...')
    # sh(f'rm -rf {WORK}/*')

    # conf('keymap.plist', '~/Library/LaunchAgents/keymap.plist')

    # heads up: ssh + launchagents ignore XDG. keep any ~/.ssh/config or ~/Library/LaunchAgents you need.
    print('\n✅ Done')
