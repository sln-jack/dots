#!/usr/bin/env bash
set -euo pipefail

DOTS=$(dirname $(readlink -f "$0"))
HOST=$1
rsync -Pavr \
    --exclude prefix/bin \
    --exclude prefix/lib \
    --exclude prefix/config \
    --exclude prefix/work \
    --exclude prefix/codex/log \
    --exclude prefix/codex/sessions \
    --exclude prefix/codex/history.jsonl \
    --exclude prefix/codex/config.toml \
    --delete \
    $DOTS/ $HOST:~/.jack/

ssh $HOST bash --noprofile --norc -c '~/.jack/setup.py'
