@pkg()
def dotnet(d: Path, v: str, extra_vs: list[str] = []):
    tag = {('darwin','arm64'):'osx-arm64', ('linux','x86_64'):'linux-x64'}[(sys, arch)]
    for v in [*extra_vs, v]:
        extract(f'https://builds.dotnet.microsoft.com/dotnet/Sdk/{v}/dotnet-sdk-{v}-{tag}.tar.gz', d)
    sh(f'mkdir {d}/bin && ln -sfr {d}/dotnet {d}/bin/')
    ENV['DOTNET_ROOT'] = d

@pkg(deps={'dotnet'})
def roslyn_ls(d: Path, v: str):
    sh(f'rm -rf {WORK}/roslyn || true')
    sh(f'git clone https://github.com/dotnet/roslyn {WORK}/roslyn --depth 1 --branch VSCode-CSharp-{v}')

    dotnet = PKGS/'dotnet'/'bin'/'dotnet'
    sh(f'{dotnet} publish -c Release -o {d} -p:UseAppHost=true -p:IncludeSymbols=false -p:DebugType=None -p:EnableWindowsTargeting=false', 
       cwd=WORK/'roslyn/src/LanguageServer/Microsoft.CodeAnalysis.LanguageServer')

    sh(f'mkdir {d}/bin && ln -sfr {d}/Microsoft.CodeAnalysis.LanguageServer {d}/bin/')

@pkg(deps=['clang'])
def netcoredbg(d: Path, v: str):
    extract(f'https://github.com/Samsung/netcoredbg/archive/refs/tags/{v}.tar.gz', WORK)
    cc  = PKGS/'clang/bin/clang'
    cxx = PKGS/'clang/bin/clang++'
    build_cmake(WORK/f'netcoredbg-{v}', d, f'-DCMAKE_C_COMPILER={cc}', f'-DCMAKE_CXX_COMPILER={cxx}')
    sh(f'mkdir {d}/bin && ln -sfr {d}/netcoredbg {d}/bin/')

if sys == 'linux':
    # C#
    dotnet('10.0.100-rc.2.25502.107', ['9.0.306', '8.0.415'])
    roslyn_ls('2.93.22')
    netcoredbg('3.1.2-1054')
