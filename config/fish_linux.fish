# Setup Nix
. ~/.nix-profile/etc/profile.d/nix.fish

# Setup PATH
set -x PATH ~/.cargo/bin ~/.nix-profile/bin /nix/var/nix/profiles/default/bin $fish_user_paths ~/.local/bin /usr/local/bin /usr/bin /usr/sbin /sbin /bin
