#!/usr/bin/env python3

import os, platform, subprocess, shutil, stat, fnmatch
from pathlib import Path

#------ Environment ------------------------------------------------------------------------------------------

ROOT = Path(__file__).resolve().parent
PREFIX = ROOT/'prefix'
PKGS = PREFIX/'pkgs'
WORK = PREFIX/'work'
CACHE = PREFIX/'cache'

PREFIX.mkdir(parents=True, exist_ok=True)

sys  = platform.system().lower()  # linux  | darwin
arch = platform.machine().lower() # x86_64 | arm64
host = os.uname().nodename        # navi
cpus = str(os.cpu_count() or 1)
triple = {
    ('x86_64','linux'): 'x86_64-unknown-linux-gnu',
    ('arm64','darwin'): 'aarch64-apple-darwin',
}[(arch, sys)]

def hosts(*patterns): return any(fnmatch.fnmatch(host, p) for p in patterns)
if hosts('monolith', 'dsk-*'): kind = 'desktop'
else: kind = 'server'

print('Probing environment...')
print(f'  Host: {host}')
print(f'  Kind: {kind}')
print(f'  System: {sys}-{arch}')
print(f'  CPUs: {cpus}')

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

def install(exe: Path, d: Path):
    sh(f'mkdir -p {d}/bin')
    sh(f'chmod +x {exe}')
    sh(f'mv {exe} {d}/bin/')

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
    path = f'PATH="{ninja}/bin:$PATH"'
    sh(f'{env} {path} CC={clang} CXX={clang}++ CC_LD=lld CXX_LD=lld {meson} setup build --prefix={prefix} {" ".join(args)}', cwd=src)
    sh(f'{env} {path} {meson} compile -C build', cwd=src)
    sh(f'{env} {path} {meson} install -C build', cwd=src)

def build_cargo(d: Path, v: str, crate: str, env: str = ''):
    rust = PKGS/'rust'
    cargo = f'RUSTUP_HOME={rust}/rustup CARGO_HOME={CACHE}/cargo PATH="{rust}/bin:$PATH" cargo'
    sh(f'{env} {cargo} install {crate}@{v} --locked --root {d}')

def build_pip(d: Path, v: str, package: str):
    pip = PKGS/'python/bin/pip3'
    sh(f'{pip} install {package}=={v} --prefix={d}')

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
    extract('https://github.com/westes/flex/files/981163/flex-2.6.4.tar.gz', WORK)
    build_autotools(WORK/'flex-2.6.4', d, f'PATH="{m4}/bin:$PATH"')

@pkg()
def pkgconf(d: Path, v: str):
    extract(f'https://distfiles.dereferenced.org/pkgconf/pkgconf-{v}.tar.xz', WORK)
    build_autotools(WORK/f'pkgconf-{v}', d)
    sh(f'ln -sf pkgconf {d}/bin/pkg-config')

#@pkg(deps={'glib', 'pkgconf', 'pcre2', 'libffi'})
#def pkgconfig(d: Path, v: str):
#    pkgconf = PKGS/'pkgconf/bin/pkgconf'
#    glib = PKGS/'glib/lib/pkgconfig'
#    pcre2 = PKGS/'pcre2/lib/pkgconfig'
#    libffi = PKGS/'libffi/lib/pkgconfig'
#    pkg_config_path = f'{glib}:{pcre2}:{libffi}'
#    extract(f'https://pkgconfig.freedesktop.org/releases/pkg-config-{v}.tar.gz', WORK)
#    build_autotools(WORK/f'pkg-config-{v}', d, f'PKG_CONFIG="{pkgconf}"', f'PKG_CONFIG_PATH="{pkg_config_path}"')

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
        '-DLLVM_TARGETS_TO_BUILD="X86;AArch64"',
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
    vars = f'RUSTUP_HOME={d}/rustup CARGO_HOME={d}'
    sh(f'curl -L https://static.rust-lang.org/rustup/dist/{triple}/rustup-init -o {WORK}/rustup-init')
    sh(f'chmod +x {WORK}/rustup-init')
    sh(f'RUSTUP_HOME={d}/rustup CARGO_HOME={d} {WORK}/rustup-init --default-toolchain {v} --component rust-analyzer --no-modify-path -y')
    sh(f'{vars} {WORK}/rustup-init --default-toolchain {v} --no-modify-path -y')
    sh(f'{vars} PATH="{d}/bin:$PATH" rustup component remove rust-docs')

@pkg()
def node(d: Path, v: str):
    tag = {('linux','x86_64'):'linux-x64', ('darwin','arm64'):'darwin-arm64'}[(sys, arch)]
    extract(f'https://nodejs.org/dist/v{v}/node-v{v}-{tag}.tar.xz', WORK)
    sh(f'mv {WORK}/node-v{v}-{tag}/* {d}')

@pkg(deps={'cmake', 'rust'})
def fish(d: Path, v: str):
    rust = PKGS/'rust'
    vars = f'PATH="{rust}/bin:$PATH" RUSTUP_HOME={rust}/rustup CARGO_HOME={rust}'

    extract(f'https://github.com/fish-shell/fish-shell/releases/download/{v}/fish-{v}.tar.xz', WORK)
    build_cmake(WORK/f'fish-{v}', d, env=vars)

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

@pkg()
def codex(d: Path, v: str):
    tag = triple.replace('gnu', 'musl')
    extract(f'https://github.com/openai/codex/releases/download/rust-v{v}/codex-{tag}.tar.gz', WORK)
    install(WORK/f'codex-{tag}', d)
    sh(f'mv {d}/bin/codex-{tag} {d}/bin/codex')

# Get latest version with `curl -LO https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/stable`
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
def zig(d: Path, v: str):
    tag = {('linux','x86_64'):'x86_64-linux', ('darwin','arm64'):'aarch64-macos'}[(sys, arch)]
    extract(f'https://ziglang.org/download/{v}/zig-{tag}-{v}.tar.xz', WORK)
    sh(f'mv {WORK}/zig-{tag}-{v} {d}/zig')
    sh(f'mkdir -p {d}/bin && ln -sf ../zig/zig {d}/bin/')

@pkg(deps={'rust', 'zig'})
def cargo_zigbuild(d: Path, v: str):
    build_cargo(d, v, 'cargo-zigbuild')

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
    bison = PKGS/'bison'
    flex = PKGS/'flex'
    extract(f'https://ftp.postgresql.org/pub/source/v{v}/postgresql-{v}.tar.bz2', WORK)
    src = WORK/f'postgresql-{v}'
    sh(f'PATH="{bison}/bin:{flex}/bin:$PATH" ./configure --prefix={d} --without-icu --without-lz4 --without-zstd --with-openssl', cwd=src)
    for t in ['src/interfaces/libpq', 'src/bin/pg_dump', 'src/bin/psql']:
        sh(f'PATH="{bison}/bin:{flex}/bin:$PATH" make -j{cpus} && make install', cwd=src/t)

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

@pkg(deps={'rust'})
def dua(d: Path, v: str):
    build_cargo(d, v, 'dua-cli')

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
        'rawshark','sharkd','tfshark','capinfos','editcap',
        'mergecap','reordercap','text2pcap','randpkt','randpktdump',
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
    bison = PKGS/'bison'
    flex = PKGS/'flex'
    extract(f'https://www.tcpdump.org/release/libpcap-{v}.tar.xz', WORK)
    build_autotools(WORK/f'libpcap-{v}', d, '--disable-dbus', '--enable-shared', '--enable-static', env=f'PATH="{bison}/bin:{flex}/bin:$PATH"')

@pkg()
def netcat(d: Path, v: str):
    extract(f'https://sourceforge.net/projects/netcat/files/netcat/{v}/netcat-{v}.tar.gz', WORK)
    build_autotools(WORK/f'netcat-{v}', d)

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

@pkg(deps={'pkgconf'})
def xorgproto(d: Path, v: str):
    extract(f'https://www.x.org/archive/individual/proto/xorgproto-{v}.tar.xz', WORK)
    build_autotools(WORK/f'xorgproto-{v}', d,
        f'PKG_CONFIG="{PKGS}/pkgconf/bin/pkgconf"')

@pkg(deps={'pkgconf'})
def xtrans(d: Path, v: str):
    extract(f'https://www.x.org/archive/individual/lib/xtrans-{v}.tar.xz', WORK)
    build_autotools(WORK/f'xtrans-{v}', d,
        f'PKG_CONFIG="{PKGS}/pkgconf/bin/pkgconf"')

@pkg(deps={'xorgproto'})
def libxau(d: Path, v: str):
    xorgproto = PKGS/'xorgproto/share/pkgconfig'
    extract(f'https://www.x.org/archive/individual/lib/libXau-{v}.tar.xz', WORK)
    build_autotools(WORK/f'libXau-{v}', d,
        f'PKG_CONFIG="{PKGS}/pkgconf/bin/pkgconf"',
        f'PKG_CONFIG_PATH="{xorgproto}"')

@pkg(deps={'xorgproto'})
def libxdmcp(d: Path, v: str):
    xorgproto = PKGS/'xorgproto/share/pkgconfig'
    extract(f'https://www.x.org/archive/individual/lib/libXdmcp-{v}.tar.xz', WORK)
    build_autotools(WORK/f'libXdmcp-{v}', d,
        f'PKG_CONFIG="{PKGS}/pkgconf/bin/pkgconf"',
        f'PKG_CONFIG_PATH="{xorgproto}"')

@pkg(deps={'python', 'pkgconf'})
def xcb_proto(d: Path, v: str):
    python = PKGS/'python/bin/python3'
    extract(f'https://xcb.freedesktop.org/dist/xcb-proto-{v}.tar.xz', WORK)
    build_autotools(WORK/f'xcb-proto-{v}', d,
        f'PKG_CONFIG="{PKGS}/pkgconf/bin/pkgconf"',
        f'PYTHON="{python}"')

@pkg(deps={'libxau', 'libxdmcp', 'xcb_proto'})
def libxcb(d: Path, v: str):
    xorgproto = PKGS/'xorgproto/share/pkgconfig'
    libxau = PKGS/'libxau/lib/pkgconfig'
    libxdmcp = PKGS/'libxdmcp/lib/pkgconfig'
    xcb_proto = PKGS/'xcb_proto/share/pkgconfig'
    pkg_config_path = f'{xorgproto}:{libxau}:{libxdmcp}:{xcb_proto}'
    python = PKGS/'python/bin/python3'
    extract(f'https://xcb.freedesktop.org/dist/libxcb-{v}.tar.xz', WORK)
    build_autotools(WORK/f'libxcb-{v}', d,
        f'PKG_CONFIG="{PKGS}/pkgconf/bin/pkgconf"',
        f'PKG_CONFIG_PATH="{pkg_config_path}"',
        f'PYTHON="{python}"')

@pkg(deps={'xtrans', 'libxcb'})
def libx11(d: Path, v: str):
    xorgproto = PKGS/'xorgproto/share/pkgconfig'
    xtrans = PKGS/'xtrans/share/pkgconfig'
    libxau = PKGS/'libxau/lib/pkgconfig'
    libxdmcp = PKGS/'libxdmcp/lib/pkgconfig'
    xcb_proto = PKGS/'xcb_proto/share/pkgconfig'
    libxcb = PKGS/'libxcb/lib/pkgconfig'
    pkg_config_path = f'{xorgproto}:{xtrans}:{libxau}:{libxdmcp}:{xcb_proto}:{libxcb}'
    extract(f'https://www.x.org/archive/individual/lib/libX11-{v}.tar.xz', WORK)
    build_autotools(WORK/f'libX11-{v}', d,
        f'PKG_CONFIG="{PKGS}/pkgconf/bin/pkgconf"',
        f'PKG_CONFIG_PATH="{pkg_config_path}"')

@pkg(deps={'libx11'})
def libxext(d: Path, v: str):
    xorgproto = PKGS/'xorgproto/share/pkgconfig'
    libxau = PKGS/'libxau/lib/pkgconfig'
    libxdmcp = PKGS/'libxdmcp/lib/pkgconfig'
    libxcb = PKGS/'libxcb/lib/pkgconfig'
    libx11 = PKGS/'libx11/lib/pkgconfig'
    pkg_config_path = f'{xorgproto}:{libxau}:{libxdmcp}:{libxcb}:{libx11}'
    extract(f'https://www.x.org/archive/individual/lib/libXext-{v}.tar.xz', WORK)
    build_autotools(WORK/f'libXext-{v}', d,
        f'PKG_CONFIG="{PKGS}/pkgconf/bin/pkgconf"',
        f'PKG_CONFIG_PATH="{pkg_config_path}"')

@pkg(deps={'libxext'})
def libice(d: Path, v: str):
    xorgproto = PKGS/'xorgproto/share/pkgconfig'
    xtrans = PKGS/'xtrans/share/pkgconfig'
    libxau = PKGS/'libxau/lib/pkgconfig'
    libxdmcp = PKGS/'libxdmcp/lib/pkgconfig'
    libxcb = PKGS/'libxcb/lib/pkgconfig'
    libx11 = PKGS/'libx11/lib/pkgconfig'
    libxext = PKGS/'libxext/lib/pkgconfig'
    pkg_config_path = f'{xorgproto}:{xtrans}:{libxau}:{libxdmcp}:{libxcb}:{libx11}:{libxext}'
    extract(f'https://www.x.org/archive/individual/lib/libICE-{v}.tar.xz', WORK)
    build_autotools(WORK/f'libICE-{v}', d,
        f'PKG_CONFIG="{PKGS}/pkgconf/bin/pkgconf"',
        f'PKG_CONFIG_PATH="{pkg_config_path}"')

@pkg(deps={'libice'})
def libsm(d: Path, v: str):
    xorgproto = PKGS/'xorgproto/share/pkgconfig'
    xtrans = PKGS/'xtrans/share/pkgconfig'
    libxau = PKGS/'libxau/lib/pkgconfig'
    libxdmcp = PKGS/'libxdmcp/lib/pkgconfig'
    libxcb = PKGS/'libxcb/lib/pkgconfig'
    libx11 = PKGS/'libx11/lib/pkgconfig'
    libxext = PKGS/'libxext/lib/pkgconfig'
    libice = PKGS/'libice/lib/pkgconfig'
    pkg_config_path = f'{xorgproto}:{xtrans}:{libxau}:{libxdmcp}:{libxcb}:{libx11}:{libxext}:{libice}'
    extract(f'https://www.x.org/archive/individual/lib/libSM-{v}.tar.xz', WORK)
    build_autotools(WORK/f'libSM-{v}', d,
        f'PKG_CONFIG="{PKGS}/pkgconf/bin/pkgconf"',
        f'PKG_CONFIG_PATH="{pkg_config_path}"')

@pkg(deps={'libsm'})
def libxt(d: Path, v: str):
    xorgproto = PKGS/'xorgproto/share/pkgconfig'
    xtrans = PKGS/'xtrans/share/pkgconfig'
    libxau = PKGS/'libxau/lib/pkgconfig'
    libxdmcp = PKGS/'libxdmcp/lib/pkgconfig'
    libxcb = PKGS/'libxcb/lib/pkgconfig'
    libx11 = PKGS/'libx11/lib/pkgconfig'
    libxext = PKGS/'libxext/lib/pkgconfig'
    libice = PKGS/'libice/lib/pkgconfig'
    libsm = PKGS/'libsm/lib/pkgconfig'
    pkg_config_path = f'{xorgproto}:{xtrans}:{libxau}:{libxdmcp}:{libxcb}:{libx11}:{libxext}:{libice}:{libsm}'
    extract(f'https://www.x.org/archive/individual/lib/libXt-{v}.tar.xz', WORK)
    build_autotools(WORK/f'libXt-{v}', d,
        f'PKG_CONFIG="{PKGS}/pkgconf/bin/pkgconf"',
        f'PKG_CONFIG_PATH="{pkg_config_path}"')

@pkg(deps={'libxt'})
def libxmu(d: Path, v: str):
    xorgproto = PKGS/'xorgproto/share/pkgconfig'
    xtrans = PKGS/'xtrans/share/pkgconfig'
    libxau = PKGS/'libxau/lib/pkgconfig'
    libxdmcp = PKGS/'libxdmcp/lib/pkgconfig'
    libxcb = PKGS/'libxcb/lib/pkgconfig'
    libx11 = PKGS/'libx11/lib/pkgconfig'
    libxext = PKGS/'libxext/lib/pkgconfig'
    libice = PKGS/'libice/lib/pkgconfig'
    libsm = PKGS/'libsm/lib/pkgconfig'
    libxt = PKGS/'libxt/lib/pkgconfig'
    pkg_config_path = f'{xorgproto}:{xtrans}:{libxau}:{libxdmcp}:{libxcb}:{libx11}:{libxext}:{libice}:{libsm}:{libxt}'
    extract(f'https://www.x.org/archive/individual/lib/libXmu-{v}.tar.xz', WORK)
    build_autotools(WORK/f'libXmu-{v}', d,
        f'PKG_CONFIG="{PKGS}/pkgconf/bin/pkgconf"',
        f'PKG_CONFIG_PATH="{pkg_config_path}"')

@pkg(deps={'libx11'})
def libxpm(d: Path, v: str):
    xorgproto = PKGS/'xorgproto/share/pkgconfig'
    libxau = PKGS/'libxau/lib/pkgconfig'
    libxdmcp = PKGS/'libxdmcp/lib/pkgconfig'
    libxcb = PKGS/'libxcb/lib/pkgconfig'
    libx11 = PKGS/'libx11/lib/pkgconfig'
    pkg_config_path = f'{xorgproto}:{libxau}:{libxdmcp}:{libxcb}:{libx11}'
    extract(f'https://www.x.org/archive/individual/lib/libXpm-{v}.tar.xz', WORK)
    build_autotools(WORK/f'libXpm-{v}', d,
        f'PKG_CONFIG="{PKGS}/pkgconf/bin/pkgconf"',
        f'PKG_CONFIG_PATH="{pkg_config_path}"')

@pkg(deps={'libxmu', 'libxpm'})
def libxaw(d: Path, v: str):
    xorgproto = PKGS/'xorgproto/share/pkgconfig'
    xtrans = PKGS/'xtrans/share/pkgconfig'
    libxau = PKGS/'libxau/lib/pkgconfig'
    libxdmcp = PKGS/'libxdmcp/lib/pkgconfig'
    libxcb = PKGS/'libxcb/lib/pkgconfig'
    libx11 = PKGS/'libx11/lib/pkgconfig'
    libxext = PKGS/'libxext/lib/pkgconfig'
    libice = PKGS/'libice/lib/pkgconfig'
    libsm = PKGS/'libsm/lib/pkgconfig'
    libxt = PKGS/'libxt/lib/pkgconfig'
    libxmu = PKGS/'libxmu/lib/pkgconfig'
    libxpm = PKGS/'libxpm/lib/pkgconfig'
    pkg_config_path = f'{xorgproto}:{xtrans}:{libxau}:{libxdmcp}:{libxcb}:{libx11}:{libxext}:{libice}:{libsm}:{libxt}:{libxmu}:{libxpm}'
    extract(f'https://www.x.org/archive/individual/lib/libXaw-{v}.tar.xz', WORK)
    build_autotools(WORK/f'libXaw-{v}', d,
        f'PKG_CONFIG="{PKGS}/pkgconf/bin/pkgconf"',
        f'PKG_CONFIG_PATH="{pkg_config_path}"')

@pkg(deps={'libx11'})
def libxrender(d: Path, v: str):
    xorgproto = PKGS/'xorgproto/share/pkgconfig'
    libxau = PKGS/'libxau/lib/pkgconfig'
    libxdmcp = PKGS/'libxdmcp/lib/pkgconfig'
    libxcb = PKGS/'libxcb/lib/pkgconfig'
    libx11 = PKGS/'libx11/lib/pkgconfig'
    pkg_config_path = f'{xorgproto}:{libxau}:{libxdmcp}:{libxcb}:{libx11}'
    extract(f'https://www.x.org/archive/individual/lib/libXrender-{v}.tar.xz', WORK)
    build_autotools(WORK/f'libXrender-{v}', d,
        f'PKG_CONFIG="{PKGS}/pkgconf/bin/pkgconf"',
        f'PKG_CONFIG_PATH="{pkg_config_path}"')

@pkg(deps={'libxrender', 'freetype', 'fontconfig'})
def libxft(d: Path, v: str):
    xorgproto = PKGS/'xorgproto/share/pkgconfig'
    libxau = PKGS/'libxau/lib/pkgconfig'
    libxdmcp = PKGS/'libxdmcp/lib/pkgconfig'
    libxcb = PKGS/'libxcb/lib/pkgconfig'
    libx11 = PKGS/'libx11/lib/pkgconfig'
    libxrender = PKGS/'libxrender/lib/pkgconfig'
    freetype = PKGS/'freetype/lib/pkgconfig'
    fontconfig = PKGS/'fontconfig/lib/pkgconfig'
    pkg_config_path = f'{xorgproto}:{libxau}:{libxdmcp}:{libxcb}:{libx11}:{libxrender}:{freetype}:{fontconfig}'
    extract(f'https://www.x.org/archive/individual/lib/libXft-{v}.tar.xz', WORK)
    build_autotools(WORK/f'libXft-{v}', d,
        f'PKG_CONFIG="{PKGS}/pkgconf/bin/pkgconf"',
        f'PKG_CONFIG_PATH="{pkg_config_path}"')

@pkg(deps={'libxext'})
def libxinerama(d: Path, v: str):
    xorgproto = PKGS/'xorgproto/share/pkgconfig'
    libxau = PKGS/'libxau/lib/pkgconfig'
    libxdmcp = PKGS/'libxdmcp/lib/pkgconfig'
    libxcb = PKGS/'libxcb/lib/pkgconfig'
    libx11 = PKGS/'libx11/lib/pkgconfig'
    libxext = PKGS/'libxext/lib/pkgconfig'
    pkg_config_path = f'{xorgproto}:{libxau}:{libxdmcp}:{libxcb}:{libx11}:{libxext}'
    extract(f'https://www.x.org/archive/individual/lib/libXinerama-{v}.tar.xz', WORK)
    build_autotools(WORK/f'libXinerama-{v}', d,
        f'PKG_CONFIG="{PKGS}/pkgconf/bin/pkgconf"',
        f'PKG_CONFIG_PATH="{pkg_config_path}"')

@pkg()
def gperf(d: Path, v: str):
    extract(f'https://ftp.gnu.org/gnu/gperf/gperf-{v}.tar.gz', WORK)
    build_autotools(WORK/f'gperf-{v}', d)

@pkg()
def freetype(d: Path, v: str):
    extract(f'https://download.savannah.gnu.org/releases/freetype/freetype-{v}.tar.xz', WORK)
    build_autotools(WORK/f'freetype-{v}', d)

@pkg(deps={'freetype', 'pkgconf', 'gperf'})
def fontconfig(d: Path, v: str):
    gperf = PKGS/'gperf'
    freetype = PKGS/'freetype/lib/pkgconfig'
    extract(f'https://www.freedesktop.org/software/fontconfig/release/fontconfig-{v}.tar.xz', WORK)
    build_autotools(WORK/f'fontconfig-{v}', d,
        f'PKG_CONFIG="{PKGS}/pkgconf/bin/pkgconf"',
        f'PKG_CONFIG_PATH="{freetype}"',
        '--disable-docs',
        env=f'PATH="{gperf}/bin:$PATH"')

@pkg(deps={'libxaw', 'libxft', 'libxinerama', 'freetype'})
def xterm(d: Path, v: str):
    xorgproto = PKGS/'xorgproto/share/pkgconfig'
    xtrans = PKGS/'xtrans/share/pkgconfig'
    libxau = PKGS/'libxau/lib/pkgconfig'
    libxdmcp = PKGS/'libxdmcp/lib/pkgconfig'
    libxcb = PKGS/'libxcb/lib/pkgconfig'
    libx11 = PKGS/'libx11/lib/pkgconfig'
    libxext = PKGS/'libxext/lib/pkgconfig'
    libice = PKGS/'libice/lib/pkgconfig'
    libsm = PKGS/'libsm/lib/pkgconfig'
    libxt = PKGS/'libxt/lib/pkgconfig'
    libxmu = PKGS/'libxmu/lib/pkgconfig'
    libxpm = PKGS/'libxpm/lib/pkgconfig'
    libxaw = PKGS/'libxaw/lib/pkgconfig'
    libxrender = PKGS/'libxrender/lib/pkgconfig'
    libxft = PKGS/'libxft/lib/pkgconfig'
    libxinerama = PKGS/'libxinerama/lib/pkgconfig'
    freetype = PKGS/'freetype/lib/pkgconfig'
    pkg_config_path = f'{xorgproto}:{xtrans}:{libxau}:{libxdmcp}:{libxcb}:{libx11}:{libxext}:{libice}:{libsm}:{libxt}:{libxmu}:{libxpm}:{libxaw}:{libxrender}:{libxft}:{libxinerama}:{freetype}'
    extract(f'https://invisible-island.net/archives/xterm/xterm-{v}.tgz', WORK)
    build_autotools(WORK/f'xterm-{v}', d,
        '--enable-256-color', '--enable-wide-chars', '--enable-freetype',
        f'PKG_CONFIG="{PKGS}/pkgconf/bin/pkgconf"',
        f'PKG_CONFIG_PATH="{pkg_config_path}"')

@pkg(deps={'libx11'})
def xinit(d: Path, v: str):
    xorgproto = PKGS/'xorgproto/share/pkgconfig'
    libxau = PKGS/'libxau/lib/pkgconfig'
    libxdmcp = PKGS/'libxdmcp/lib/pkgconfig'
    libxcb = PKGS/'libxcb/lib/pkgconfig'
    libx11 = PKGS/'libx11/lib/pkgconfig'
    pkg_config_path = f'{xorgproto}:{libxau}:{libxdmcp}:{libxcb}:{libx11}'
    extract(f'https://www.x.org/archive/individual/app/xinit-{v}.tar.xz', WORK)
    build_autotools(WORK/f'xinit-{v}', d,
        f'PKG_CONFIG="{PKGS}/pkgconf/bin/pkgconf"',
        f'PKG_CONFIG_PATH="{pkg_config_path}"')

@pkg(deps={'libxmu'})
def xauth(d: Path, v: str):
    xorgproto = PKGS/'xorgproto/share/pkgconfig'
    xtrans = PKGS/'xtrans/share/pkgconfig'
    libxau = PKGS/'libxau/lib/pkgconfig'
    libxdmcp = PKGS/'libxdmcp/lib/pkgconfig'
    libxcb = PKGS/'libxcb/lib/pkgconfig'
    libx11 = PKGS/'libx11/lib/pkgconfig'
    libxext = PKGS/'libxext/lib/pkgconfig'
    libice = PKGS/'libice/lib/pkgconfig'
    libsm = PKGS/'libsm/lib/pkgconfig'
    libxt = PKGS/'libxt/lib/pkgconfig'
    libxmu = PKGS/'libxmu/lib/pkgconfig'
    pkg_config_path = f'{xorgproto}:{xtrans}:{libxau}:{libxdmcp}:{libxcb}:{libx11}:{libxext}:{libice}:{libsm}:{libxt}:{libxmu}'
    extract(f'https://www.x.org/archive/individual/app/xauth-{v}.tar.xz', WORK)
    build_autotools(WORK/f'xauth-{v}', d,
        f'PKG_CONFIG="{PKGS}/pkgconf/bin/pkgconf"',
        f'PKG_CONFIG_PATH="{pkg_config_path}"')

@pkg(deps={'rust', 'freetype', 'fontconfig'})
def neovide(d: Path, v: str):
    freetype_lib = PKGS/'freetype/lib'
    fontconfig_lib = PKGS/'fontconfig/lib'
    freetype = PKGS/'freetype/lib/pkgconfig'
    fontconfig = PKGS/'fontconfig/lib/pkgconfig'
    env = f'LIBRARY_PATH="{freetype_lib}:{fontconfig_lib}" PKG_CONFIG_PATH="{freetype}:{fontconfig}"'
    build_cargo(d, v, 'neovide', env=env)

@pkg()
def zen(d: Path, v: str):
    extract(f'https://github.com/zen-browser/desktop/releases/download/{v}/zen.linux-x86_64.tar.xz', WORK)
    sh(f'mv {WORK}/zen {d}/')
    sh(f'mkdir -p {d}/bin && ln -sf ../zen/zen {d}/bin/zen')

@pkg(deps={'libxft', 'libxinerama', 'freetype', 'fontconfig'})
def dwm(d: Path, v: str):
    incs = ' '.join(f'-I{PKGS}/{n}/include' for n in
        ('libx11', 'libxft', 'libxrender', 'libxinerama', 'fontconfig')) + f' -I{PKGS}/freetype/include/freetype2'
    libs = ' '.join(f'-L{PKGS}/{n}/lib' for n in
        ('libx11', 'libxft', 'libxrender', 'libxinerama', 'freetype', 'fontconfig')) + ' -lX11 -lXinerama -lfontconfig -lXft'
    extract(f'https://github.com/sln-jack/dwm/archive/refs/heads/master.tar.gz', WORK)
    sh(f'rm -f {WORK}/dwm-master/config.h && make -j{cpus} INCS="{incs}" LIBS="{libs}" && DESTDIR={d} make install', cwd=WORK/'dwm-master')

@pkg(deps={'libxft', 'libxinerama', 'freetype', 'fontconfig'})
def dmenu(d: Path, v: str):
    incs = ' '.join(f'-I{PKGS}/{n}/include' for n in
        ('libx11', 'libxft', 'libxrender', 'libxinerama', 'fontconfig')) + f' -I{PKGS}/freetype/include/freetype2'
    libs = ' '.join(f'-L{PKGS}/{n}/lib' for n in
        ('libx11', 'libxft', 'libxrender', 'libxinerama', 'freetype', 'fontconfig')) + ' -lX11 -lXinerama -lfontconfig -lXft'
    extract(f'https://github.com/sln-jack/dmenu/archive/refs/heads/master.tar.gz', WORK)
    sh(f'rm -f {WORK}/dmenu-master/config.h && make -j{cpus} INCS="{incs}" LIBS="{libs}" && DESTDIR={d} make install', cwd=WORK/'dmenu-master')

@pkg(deps={'automake', 'pkgconf'})
def libevdev(d: Path, v: str):
    pkgconf = PKGS/'pkgconf'
    extract(f'https://www.freedesktop.org/software/libevdev/libevdev-{v}.tar.xz', WORK)
    build_automake(
        WORK/f'libevdev-{v}', d,
        '--enable-static', '--disable-shared',
        env=f'ACLOCAL_PATH="{pkgconf}/share/aclocal"'
    )

@pkg(deps={'automake', 'pkgconf'})
def libmtdev(d: Path, v: str):
    extract(f'https://bitmath.se/org/code/mtdev/mtdev-{v}.tar.gz', WORK)
    build_automake(
        WORK/f'mtdev-{v}', d,
        '--enable-static', '--disable-shared'
    )

@pkg(deps={'meson', 'ninja', 'libevdev', 'libmtdev'})
def libinput(d: Path, v: str):
    # WARNING: impure to take host libsystemd
    system = '/usr/share/pkgconfig:/usr/lib64/pkgconfig'
    libevdev = PKGS/'libevdev/lib/pkgconfig'
    libmtdev = PKGS/'libmtdev/lib/pkgconfig'
    extract(f'https://gitlab.freedesktop.org/libinput/libinput/-/archive/{v}/libinput-{v}.tar.gz', WORK)
    build_meson(
        WORK/f'libinput-{v}', d,
        '-Ddocumentation=false',
        '-Dtests=false',
        '-Ddebug-gui=false',
        '-Dlibwacom=false',
        env=f'PKG_CONFIG_PATH="{libevdev}:{libmtdev}:{system}"'
    )

@pkg(deps={'clang'})
def pugixml(d: Path, v: str):
    extract(f'https://github.com/zeux/pugixml/archive/refs/tags/v{v}.tar.gz', WORK)
    build_cmake(
        WORK/f'pugixml-{v}', d,
        '-DCMAKE_CXX_FLAGS="-stdlib=libc++"',
    )

@pkg(deps={'clang'})
def libseat(d: Path, v: str):
    # WARNING: impure to take host libsystemd
    system = '/usr/share/pkgconfig:/usr/lib64/pkgconfig'
    libinput = PKGS/f'libinput/lib64/pkgconfig'

    extract(f'https://git.sr.ht/~kennylevinsen/seatd/archive/{v}.tar.gz', WORK)
    build_meson(
        WORK/f'seatd-{v}', d,
        '-Dlibseat-seatd=disabled',
        '-Dserver=disabled',
        env=f'PKG_CONFIG_PATH="{system}:{libinput}"',
    )

@pkg(deps={'clang', 'pugixml'})
def hyprwayland_scanner(d: Path, v: str):
    pugixml = PKGS/'pugixml'
    vars = f'PKG_CONFIG_PATH="{pugixml}/lib64/pkgconfig"'

    extract(f'https://github.com/hyprwm/hyprwayland-scanner/archive/refs/tags/v{v}.tar.gz', WORK)
    build_cmake(
        WORK/f'hyprwayland-scanner-{v}', d,
        '-DCMAKE_CXX_FLAGS="-stdlib=libc++"',
        env=vars)


@pkg()
def libffi(d: Path, v: str):
    extract(f'https://github.com/libffi/libffi/releases/download/v{v}/libffi-{v}.tar.gz', WORK)
    build_autotools(WORK/f'libffi-{v}', d)

#@pkg(deps={'cmake'})
#def libexpat(d: Path, v: str):
#    extract(f'https://github.com/libexpat/libexpat/releases/download/R_{v.replace('.', '_')}/expat-{v}.tar.gz', WORK)
#    build_cmake(WORK/f'expat-{v}', d)

@pkg(deps={'meson', 'libffi', 'libexpat', 'libxml2'})
def wayland(d: Path, v: str):
    libffi = PKGS/'libffi/lib/pkgconfig'
    libexpat = PKGS/'libexpat/lib64/pkgconfig'

    extract(f'https://gitlab.freedesktop.org/wayland/wayland/-/archive/{v}/wayland-{v}.tar.gz', WORK)
    build_meson(
        WORK/f'wayland-{v}', d,
        '-Dscanner=true',
        '-Dtests=false',
        '-Ddocumentation=false',
        '-Ddtd_validation=false',
        env=f'PKG_CONFIG_PATH="{libffi}:{libexpat}"',
    )

@pkg(deps={'meson'})
def wayland_protocols(d: Path, v: str):
    wayland = PKGS/'wayland/lib64/pkgconfig'

    extract(f'https://gitlab.freedesktop.org/wayland/wayland-protocols/-/archive/{v}/wayland-protocols-{v}.tar.gz', WORK)
    build_meson(
        WORK/f'wayland-protocols-{v}', d,
        '-Dtests=false',
        env=f'PKG_CONFIG_PATH="{wayland}"',
    )

@pkg(deps={'clang', 'pixman'})
def hyprutils(d: Path, v: str):
    pixman = PKGS/'pixman/lib64/pkgconfig'

    extract(f'https://github.com/hyprwm/hyprutils/archive/refs/tags/v0.10.4.tar.gz', WORK)
    build_cmake(
        WORK/f'hyprutils-{v}', d,
        '-DCMAKE_CXX_FLAGS="-stdlib=libc++"',
        env=f'PKG_CONFIG_PATH="{pixman}"',
    )

@pkg(deps={'meson'})
def pixman(d: Path, v: str):
    extract(f'https://cairographics.org/releases/pixman-{v}.tar.gz', WORK)
    build_meson(WORK/f'pixman-{v}', d)

@pkg(deps={'meson'})
def libdisplay_info(d: Path, v: str):
    extract(f'https://gitlab.freedesktop.org/emersion/libdisplay-info/-/archive/{v}/libdisplay-info-{v}.tar.gz', WORK)
    build_meson(WORK/f'libdisplay-info-{v}', d)

@pkg()
def hwdata(d: Path, v: str):
    extract(f'https://github.com/vcrhonek/hwdata/archive/refs/tags/v{v}.tar.gz', WORK)
    build_autotools(WORK/f'hwdata-{v}', d)

@pkg(deps={'hyprutils'})
def hyprlang(d: Path, v: str):
    hyprutils = PKGS/'hyprutils/lib64/pkgconfig'

    extract(f'https://github.com/hyprwm/hyprlang/archive/refs/tags/v{v}.tar.gz', WORK)
    build_cmake(
        WORK/f'hyprlang-{v}', d,
        '-DCMAKE_CXX_FLAGS="-stdlib=libc++"',
        env=f'PKG_CONFIG_PATH="{hyprutils}"',
    )

@pkg()
def libzip(d: Path, v: str):
    extract(f'https://github.com/nih-at/libzip/archive/refs/tags/v{v}.tar.gz', WORK)
    build_cmake(
        WORK/f'libzip-{v}', d,
        '-DCMAKE_CXX_FLAGS="-stdlib=libc++"',
    )

#@pkg(deps={'m4'})
#def pcre2(d: Path, v: str):
#    m4 = PKGS/'m4'
#    extract(f'https://github.com/PCRE2Project/pcre2/archive/refs/tags/pcre2-{v}.tar.gz', WORK)
#    build_automake(WORK/f'pcre2-pcre2-{v}', d, env=f'PATH="{m4}/bin:$PATH"')

#@pkg(deps={'pcre2', 'libffi', 'pkgconf'})
#def glib(d: Path, v: str):
#    extract(f'https://gitlab.gnome.org/GNOME/glib/-/archive/{v}/glib-{v}.tar.gz', WORK)
#    src = WORK/f'glib-{v}'
#
#    pkgconf = PKGS/'pkgconf'
#    pcre2 = PKGS/'pcre2/lib/pkgconfig'
#    libffi = PKGS/'libffi/lib/pkgconfig'
#    pkg_config_path = f'{pcre2}:{libffi}'
#    sh(f'rm -rf {src}/subprojects/gvdb')
#    # TODO: pin a sha, dont use main
#    sh(f'git clone https://gitlab.gnome.org/GNOME/gvdb --depth 1 {src}/subprojects/gvdb')
#
#    build_meson(
#        src, d,
#        '-Dwrap_mode=nodownload',
#        env=f'PKG_CONFIG="{pkgconf}/bin/pkgconf" PKG_CONFIG_PATH="{pkg_config_path}"',
#    )

@pkg(deps={'glib'})
def cairo(d: Path, v: str):
    extract(f'https://cairographics.org/releases/cairo-{v}.tar.xz', WORK)
    build_meson(
        WORK/f'cairo-{v}', d,
        '-Dwrap_mode=nodownload',
    )

@pkg(deps={'hyprlang', 'libzip', 'cairo'})
def hyprcursor(d: Path, v: str):
    hyprlang = PKGS/'hyprlang/lib64/pkgconfig'
    libzip = PKGS/'libzip/lib64/pkgconfig'
    cairo = PKGS/'cairo/lib64/pkgconfig'

    extract(f'https://github.com/hyprwm/hyprcursor/archive/refs/tags/v{v}.tar.gz', WORK)
    build_cmake(
        WORK/f'hyprcursor-{v}', d,
        '-DCMAKE_CXX_FLAGS="-stdlib=libc++"',
        env=f'PKG_CONFIG_PATH="{hyprlang}:{libzip}"',
    )

@pkg(deps={'meson', 'hyprwayland_scanner', 'libinput', 'libseat', 'wayland', 'wayland_protocols', 'hyprutils'})
def aquamarine(d: Path, v: str):
    clang = PKGS/'clang/lib/x86_64-unknown-linux-gnu'
    hyprwayland_scanner = PKGS/'hyprwayland_scanner'
    libinput = PKGS/'libinput/lib64/pkgconfig'
    libseat = PKGS/'libseat/lib64/pkgconfig'
    wayland = PKGS/'wayland/lib64/pkgconfig'
    wayland_protocols = PKGS/'wayland_protocols/share/pkgconfig'
    hyprutils = PKGS/'hyprutils/lib64/pkgconfig'
    pixman = PKGS/'pixman/lib64/pkgconfig'
    libdisplay_info = PKGS/'libdisplay_info/lib64/pkgconfig'
    hwdata = PKGS/'hwdata/share/pkgconfig'

    extract(f'https://github.com/hyprwm/aquamarine/archive/refs/tags/v{v}.tar.gz', WORK)
    build_cmake(
        WORK/f'aquamarine-{v}', d,
        f'-DCMAKE_PREFIX_PATH={hyprwayland_scanner}',
        env=f'LD_LIBRARY_PATH="{clang}" PKG_CONFIG_PATH="{libseat}:{libinput}:{wayland}:{wayland_protocols}:{hyprutils}:{pixman}:{libdisplay_info}:{hwdata}"',
    )

@pkg(deps={'cmake', 'wayland', 'wayland_protocols', 'udis86', 'aquamarine', 'hyprlang', 'hyprcursor'})
def hyprland(d: Path, v: str):
    src = WORK/f'Hyprland-{v}'

    wayland = PKGS/'wayland/share/pkgconfig'
    wayland_protocols = PKGS/'wayland_protocols/share/pkgconfig'
    aquamarine = PKGS/'aquamarine/lib64/pkgconfig'
    hyprlang = PKGS/'hyprlang/lib64/pkgconfig'

    # udis86 submodule
    extract(f'https://github.com/canihavesomecoffee/udis86/archive/master.tar.gz', WORK)
    sh(f'rm -rf {src}/subprojects/udis86 && mv {WORK}/udis86-master {src}/subprojects/udis86')

    build_cmake(
        src, d,
        env=f'PKG_CONFIG_PATH="{wayland}:{wayland_protocols}:{aquamarine}:{hyprlang}"',
    )

# --- run ----------------------------------------------------------------------------------------------------
if __name__ == '__main__':
    print('\nAdding packages: base')

    # Toolchains
    pkgconf('1.1.0')
    #pkgconfig('0.29.2')
    ninja('1.13.2')
    m4('1.4.21')
    bison('3.8.2')
    flex('2.6.4')
    automake('1.18.1')
    if sys == 'macos': openssl('3.6.1')
    sqlite('3510100')
    python('3.14.4')
    if sys=='linux': clang('22.1.3')
    cmake('3.31.9')
    meson('1.9.2')
    #pcre2('10.47')
    libffi('3.5.2')
    #glib('2.86.5')
    rust('nightly')
    zig('0.15.2')
    cargo_zigbuild('0.22.1')
    node('24.12.0')
    bun('1.3.9')

    # Libs
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
    just('1.46.0')
    fzf('0.68.0')
    ripgrep('15.1.0')
    eza('0.23.4')
    fd('10.3.0')
    sd('1.0.0')
    dust('1.2.4')
    dua('2.32.2')
    gh('2.87.3')

    # Coding
    nvim('0.11.4')
    # Lua
    lua_ls('3.15.0')
    # Python
    uv('0.9.18')
    # AI
    codex('0.98.0')
    claude('2.1.114')
    # DB
    if sys == 'linux': postgres('18.3')
    sqlcmd('1.9.0')
    duckdb('1.4.4')
    influx('2.7.5')

    # Networking
    libpcap('1.10.5')
    libxml2('2.15.1')
    if sys == 'linux': netcat('0.7.1')
    gping('1.20.1')
    oha('1.12.1')
    snitch('0.2.2')

    # Gui
    if kind == 'desktop':
        xorgproto('2025.1')
        xtrans('1.6.0')
        libxau('1.0.12')
        libxdmcp('1.1.5')
        xcb_proto('1.17.0')
        libxcb('1.17.0')
        libx11('1.8.13')
        libxext('1.3.7')
        libice('1.1.2')
        libsm('1.2.6')
        libxt('1.3.1')
        libxmu('1.3.1')
        libxpm('3.5.18')
        libxaw('1.0.16')
        gperf('3.3')
        freetype('2.14.3')
        fontconfig('2.16.0')
        libxrender('0.9.12')
        libxft('2.3.9')
        libxinerama('1.1.6')
        xterm('409')
        xinit('1.4.4')
        xauth('1.1.5')
        neovide('0.15.2')
        zen('1.17.12b')

        # X11 Windowing
        dwm('6.6')
        dmenu('5.4')

    # Wayland Windowing
    # libevdev('1.12.1')
    # libmtdev('1.1.7')
    # libinput('1.30.0')
    # libseat('0.9.1')
    # libffi('3.5.2')
    # libexpat('2.7.3')
    # wayland('1.24.0')
    # wayland_protocols('1.46')
    # pixman('0.46.4')
    # hwdata('0.402')
    # libdisplay_info('0.3.0')
    # hyprutils('0.10.4')
    # pugixml('1.15')
    # hyprwayland_scanner('0.4.5')
    # aquamarine('0.10.0')
    # hyprlang('0.6.7')
    # libzip('1.11.4')
    # glib('2.86.2')
    # cairo('1.18.4')
    # hyprcursor('0.1.13')
    # hyprland('0.52.2')

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
    # Binaries
    for dir in ['bin', 'lib']:
        dst = PREFIX/dir
        sh(f'rm -rf {dst} && mkdir {dst}')
        for pkg in sorted(PKGS.iterdir()):
            src = pkg/dir
            if src.is_dir():
                lnr(f'{src}/*', dst)

    # Python site-packages: symlink all package site-packages into prefix/lib/python/site-packages
    dst = PREFIX/'lib'/'python'/'site-packages'
    dst.mkdir(parents=True, exist_ok=True)
    for pydir in sorted(PKGS.glob('*/lib/python*/site-packages')):
        for item in pydir.iterdir():
            link = dst/item.name
            if not link.exists():
                link.symlink_to(os.path.relpath(item, dst))
    # Config
    def conf(src_name, dst_name=None):
        target = ROOT/'config'/src_name
        link = PREFIX/'config'/(dst_name or src_name)
        rel = os.path.relpath(target, link.parent)
        sh(f'mkdir -p {link.parent}')
        sh(f'ln -sf {rel} {link}')

    sh(f'rm -rf {PREFIX}/config && mkdir {PREFIX}/config')
    conf('git')
    conf('tmux.conf', 'tmux/tmux.conf')
    conf('nvim')
    conf('fish/config.fish')
    conf('direnv.toml')
    conf('starship.toml')
    conf('Xresources')
    conf('neovide.toml', 'neovide/config.toml')
    conf('podman-storage.conf', 'containers/storage.conf')
    if sys == 'linux':
        conf('fish/linux.fish', 'fish/conf.d/linux.fish')
    if sys == 'darwin':
        conf('fish/macos.fish', 'fish/conf.d/macos.fish')
        conf('ghostty.conf', 'ghostty/config')
        conf('aerospace.toml', 'aerospace/aerospace.toml')
    sh(f'mkdir -p {PREFIX}/config/codex')
    sh(f'ln -s ~/.config/* {PREFIX}/config/ 2>/dev/null || true')

    print('Cleaning up...')
    # sh(f'rm -rf {WORK}/*')

    # conf('keymap.plist', '~/Library/LaunchAgents/keymap.plist')

    # heads up: ssh + launchagents ignore XDG. keep any ~/.ssh/config or ~/Library/LaunchAgents you need.
    print('\n✅ Done')
