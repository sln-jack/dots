#!/usr/bin/env bash
set -euo pipefail

DOTS=$(dirname $(readlink -f "$0"))
HOST=$1
rsync -Pavzr \
    --exclude prefix/bin \
    --exclude prefix/lib \
    --exclude prefix/config \
    --exclude prefix/work \
    --delete \
    $DOTS/ $HOST:~/.jack/

ssh $HOST bash -c '~/.jack/setup.py'
