# dsh 0.2.1-alpha.1 can only bind 127.0.0.1 or 0.0.0.0 and its --host refuses
# the latter, so this writes a webserver config overlay instead; newer dsh
# rejects 0.0.0.0 and binds the container address through --host.
# To remove once the image pins dsh >= 0.2.1-alpha.2: delete this file, its
# COPY line in the Dockerfile and the `legacy` branch in entrypoint.sh.

needs_legacy_bind() {
  ver=$(node -p '
    const p = require("path"), g = process.argv[1];
    const dsh = p.dirname(require.resolve("@deepseek-ai/dsh/package.json", { paths: [g] }));
    require(require.resolve("@deepseek-ai/dsh-web-app/package.json", { paths: [dsh] })).version
  ' "$(npm root -g)" 2>/dev/null) || return 1
  [ "$ver" = "0.2.1-alpha.1" ]
}

legacy_bind_patch() {
  host=${DSH_HOST:-0.0.0.0}
  case "$host" in
    0.0.0.0|127.0.0.1) ;;
    *) echo "entrypoint: DSH_HOST must be 0.0.0.0 or 127.0.0.1 on dsh 0.2.1-alpha.1 (got '$host')" >&2; return 1 ;;
  esac
  # The webserver row's whole config is replaced by a patch, so its bundle
  # values (compression on 0.2.1-alpha.1) are restated literally.
  cat > /tmp/listen.patch.yml <<EOF
- id: webserver
  config:
    host: $host
    port: $LISTEN_PORT
    compression: gzip
    compressionLevel: 1
    compressionThresholdBytes: 1024
EOF
  echo /tmp/listen.patch.yml
}
