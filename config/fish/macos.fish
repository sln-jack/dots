# Remove junk
set -e __CFBundleIdentifier
set -e __CF_USER_TEXT_ENCODING
set -e DISPLAY
set -e GHOSTTY_RESOURCES_DIR
set -e GHOSTTY_BIN_DIR
set -e GHOSTTY_SHELL_INTEGRATION_NO_SUDO
set -e TERM_PROGRAM_VERSION
set -e XDG_DATA_DIRS
set -e XPC_SERVICE_NAME
set -e XPC_FLAGS

# Setup Secretive ssh agent
set -x SSH_AUTH_SOCK /Users/foltz/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh
