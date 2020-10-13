#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

if [ "${MDNS_NAME:-}" ]; then
  goello-server -name "$MDNS_NAME" -host "$MDNS_HOST" -port "$PORT" -type "$MDNS_TYPE" &
fi

cd /boot/bin/rudder-transformer
node ./destTransformer.js &

exec caddy run -config /config/caddy/main.conf --adapter caddyfile "$@"
