#!/bin/sh
# sync_lualib.sh -- install the files OpenResty needs into a lualib directory.
#
# WHY THIS EXISTS
#   openresty/nginx.conf now points lua_package_path at /app (the repo, mounted
#   read-only) rather than at an installed copy. That is the recommended setup:
#   an installed copy can silently drift from the repo, and one did on the
#   machine this was written on.
#
#   This script is for BARE-METAL installs where you are not running the
#   container and would rather point at a directory than mount the repo.
#
#   WARNING: this DOES create a second copy, which is the exact drift hazard
#   described above. Re-run it after every change to the repo. `make -q`-style
#   drift checks do not exist here; use this to compare:
#
#       tools/sync_lualib.sh --check
#
# USAGE
#   tools/sync_lualib.sh [DEST]      default: /usr/local/openresty/site/lualib
#   tools/sync_lualib.sh --check      report drift, change nothing
#
set -e

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-/usr/local/openresty/site/lualib}"

# The runtime closure. core/*.lua is deliberately absent: those modules require
# bare names ("abi", "core") that resolve only through the package.preload
# aliases calyx_bundle.lua registers, so they are never read from disk.
FILES="init.lua effect_contract.lua hardened.lua calyx_bundle.lua session_fsm.lua"
LUALIB="nginx_host.lua mock_data.lua stream_mock.lua"

usage() { sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
[ "$1" = "-h" ] || [ "$1" = "--help" ] && usage

if [ "$1" = "--check" ]; then
    DRIFT=0
    for f in $FILES; do
        if ! cmp -s "$REPO/$f" "$DEST/$f"; then
            echo "  DRIFT  $f"; DRIFT=1
        fi
    done
    for f in $LUALIB; do
        if ! cmp -s "$REPO/openresty/lualib/$f" "$DEST/$f"; then
            echo "  DRIFT  lualib/$f"; DRIFT=1
        fi
    done
    if ! cmp -s "$REPO/openresty/lualib/calyx/session_fsm.lua" "$DEST/calyx/session_fsm.lua"; then
        echo "  DRIFT  lualib/calyx/session_fsm.lua"; DRIFT=1
    fi
    [ "$DRIFT" -eq 0 ] && echo "  in sync with $REPO"
    exit "$DRIFT"
fi

mkdir -p "$DEST/calyx"
for f in $FILES; do
    cp "$REPO/$f" "$DEST/$f"
    echo "  installed $f"
done
for f in $LUALIB; do
    cp "$REPO/openresty/lualib/$f" "$DEST/$f"
    echo "  installed lualib/$f"
done
cp "$REPO/openresty/lualib/calyx/session_fsm.lua" "$DEST/calyx/session_fsm.lua"
echo "  installed lualib/calyx/session_fsm.lua"

cat <<EOF

Installed to $DEST

Now point openresty/nginx.conf at it. The path and content_by_lua_file
directives are currently /app/... ; change them to:

    lua_package_path "$DEST/?.lua;$DEST/calyx/?.lua;/usr/local/openresty/lualib/?.lua;;";
    content_by_lua_file $DEST/nginx_host.lua;

Keep /usr/local/openresty/lualib in lua_package_path -- that is OpenResty's own
lualib (resty.core and friends), not this project's files. Removing it makes the
container fail to start with "no file 'resty/core'".

Verify with:  BASE=http://127.0.0.1:8080 sh openresty/smoke.sh
Check drift with:  tools/sync_lualib.sh --check
EOF