#!/bin/sh
# Runs dsh web as the node user. The container is the sandbox boundary, so the
# image offers only the danger-full-access preset (see docker.patch.yml).
set -eu

PUID=${PUID:-1000}
PGID=${PGID:-1000}
groupmod -o -g "$PGID" node
usermod -o -u "$PUID" node

# First start: seed the data volume with the template home built into the image
# (a web profile that already has ds-bot installed).
if [ ! -d /data/profiles/web ]; then
  mkdir -p /data
  cp -a /opt/dsh-template/. /data/
  chown -R node:node /data
fi
# Every start: /data itself must be writable by node; the files below keep the
# ownership they got on first start or from the host.
chown node:node /data

mkdir -p /workspace
# Only claim an empty /workspace; a populated share keeps its owners.
if [ -z "$(ls -A /workspace)" ]; then
  chown node:node /workspace
fi

# Keep an existing volume's ds-bot in step with the image. A failed reinstall
# is logged but never blocks the start — the old plugin keeps working.
installed_ver=$(jq -r .version /data/profiles/web/node_modules/ds-bot/package.json 2>/dev/null || echo missing)
image_ver=$(jq -r .version /opt/dsh-template/profiles/web/node_modules/ds-bot/package.json)
if [ "$installed_ver" != "$image_ver" ]; then
  echo "entrypoint: ds-bot $installed_ver -> $image_ver, reinstalling into the web profile"
  HOME=/home/node gosu node dsh plugin --profile web add /opt/ds-bot/ds-bot.tgz \
    || echo "entrypoint: ds-bot reinstall failed; continuing with $installed_ver" >&2
fi

# DSH_LISTEN_PORT only matters with network_mode: host — published ports
# always map to 3080 inside.
LISTEN_PORT=${DSH_LISTEN_PORT:-3080}
case "$LISTEN_PORT" in
  ''|*[!0-9]*) echo "entrypoint: DSH_LISTEN_PORT must be a port number (got '$LISTEN_PORT')" >&2; exit 1 ;;
esac

# Bind address. dsh binds one concrete interface address (--host); the
# container's own address is trusted by the Host fence, and DSH_TRUSTED_HOST
# names the addresses browsers use. DSH_HOST=127.0.0.1 keeps it on loopback.
LEGACY=/opt/ds-bot/legacy-bind-alpha1.sh
legacy=0
if [ -f "$LEGACY" ]; then
  if ! . "$LEGACY"; then
    echo "entrypoint: failed to load $LEGACY" >&2
    exit 1
  fi
  if needs_legacy_bind; then legacy=1; fi
fi

# --patch is a dsh option and must precede the app's own flags.
if [ "$legacy" = 1 ]; then
  listen_patch=$(legacy_bind_patch)
  set -- dsh --profile web --patch /opt/ds-bot/docker.patch.yml \
    --patch "$listen_patch" --no-open "$@"
else
  set -- dsh --profile web --patch /opt/ds-bot/docker.patch.yml --no-open \
    --host "${DSH_HOST:-$(hostname -i | awk '{print $1}')}" --port "$LISTEN_PORT" "$@"
fi

if [ -n "${DSH_TRUSTED_HOST:-}" ]; then
  old_ifs=$IFS
  IFS=','
  for trusted in $DSH_TRUSTED_HOST; do
    [ -n "$trusted" ] && set -- "$@" --trusted-host "$trusted"
  done
  IFS=$old_ifs
fi
[ -n "${DSH_PUBLIC_URL:-}" ] && set -- "$@" --public-url "$DSH_PUBLIC_URL"

export HOME=/home/node
cd /workspace
exec gosu node "$@"
