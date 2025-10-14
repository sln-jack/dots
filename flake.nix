{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            (self: super: {
              ripgrep = super.ripgrep.override { withPCRE2 = true; };
            })
          ];
        };

        common = with pkgs; [
          # Shell
          fish      # Shell
          starship  # Shell prompt
          fasd      # Directory navigation
          direnv    # Directory rc files
          eza       # Fancy ls
          tmux      # Terminal multiplexer
          yazi      # File manager
          neovim    # Editor
          neovide   # Editor GUI

          # Toolchains
          rustup        # Rust toolchain manager
          bacon         # Rust TUI
          cargo-watch   # Rust watcher
          cargo-expand  # Rust macro expander
          uv            # Python
          mise          # Generic toolchain manager
          go            # Go
          gopls         # Go LSP
          claude-code   # Slop

          # LSP
          lua-language-server
          nil  # Nix
          nixd # Nix but different

          # Text
          ripgrep  # Find text
          fzf      # Find text fuzzily
          fd       # Find files
          sd       # Find/replace in files
          jq       # Query JSON
          yq       # Query YAML
          moar     # Fancy pager
          delta    # Fancy diffs
          tokei    # Count LoC
          gnused   # Because the BSD one is weird

          # Measurement
          htop       # System metrics
          btop       # Cooler system metrics
          gping      # Ping metrics
          hyperfine  # Command timing
          dust       # Disk usage
          gnuplot    # Charts
          nmap       # Port scanning

          # Media
          ffmpeg       # Video editing
          mpv          # Video playback
          imagemagick  # Image editing
          yt-dlp       # YT/insta/etc downloader
          xh           # HTTP requests
          oha          # HTTP load tester

          # Utils
          spacer       # Inactivity spacers
          kondo        # Clean build artifacts
          watch        # Watch stuff
          rar          # I didn't pay for WinRAR

          # C stuff
          ccache
          ninja
          cmake
          pkg-config
          openssl
          util-linux  # setsid
        ];

        macos = pkgs.lib.optionals pkgs.stdenv.isDarwin (with pkgs; []);

        libs = [
          (pkgs.writeTextFile {
            name = "nix-libs-fish";
            destination = "/lib/nix.fish";
            text = ''
              if not contains "${pkgs.openssl.dev}/lib/pkgconfig" $PKG_CONFIG_PATH
              set -gx PKG_CONFIG_PATH "${pkgs.openssl.dev}/lib/pkgconfig" $PKG_CONFIG_PATH
              end
            '';
          })
        ];

      in {
        packages.dots = pkgs.buildEnv {
          name = "dots";
          paths = common ++ libs;
        };
        packages.dots-macos = pkgs.buildEnv {
          name = "dots-macos";
          paths = common ++ macos ++ libs;
        };
      }
    );
}
