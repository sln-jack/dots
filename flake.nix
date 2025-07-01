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
          neovim    # Editor
          yazi      # File manager

          # Toolchains
          rustup        # Rust toolchain manager
          bacon         # Rust TUI
          cargo-watch   # Rust watcher
          cargo-expand  # Rust macro expander
          uv            # Python
          mise          # Generic toolchain manager
          nil           # Nix language server
          nixd          # Nix language server 2
          go            # Go
          claude-code   # Anthropic coding agent
          git           # Git
          git-lfs       # Git large file support
          gh            # Github CLI

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

          # Measurement
          htop       # System metrics
          gping      # Ping metrics
          hyperfine  # Command timing
          dust       # Disk usage

          # Media
          ffmpeg       # Video editing
          imagemagick  # Image editing
          yt-dlp       # YT/insta/etc downloader
          xh           # HTTP requests
          oha          # HTTP load tester

          # Utils
          spacer  # Inactivity spacers
          kondo   # Clean build artifacts

          # C stuff
          pkg-config
          openssl
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
        packages.dots-macos = pkgs.buildEnv {
          name = "dots-macos";
          paths = common ++ macos ++ libs;
        };
      }
    );
}
