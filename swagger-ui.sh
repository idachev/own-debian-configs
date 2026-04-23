#!/usr/bin/env bash
# Start a local Swagger UI for an OpenAPI spec file.
#
# Usage:
#   swagger-ui.sh <path-to-spec.yaml|json>   # start (default port 8080)
#   swagger-ui.sh -p 9090 <path>             # start on a specific port
#   swagger-ui.sh stop                       # stop & remove the container
#   swagger-ui.sh status                     # show container status

set -euo pipefail

CONTAINER=swagger-ui-local
IMAGE=swaggerapi/swagger-ui
PORT=8080

usage() {
  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

stop_container() {
  if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    docker rm -f "$CONTAINER" >/dev/null
    echo "Stopped $CONTAINER."
  else
    echo "No $CONTAINER container running."
  fi
}

case "${1:-}" in
  ''|-h|--help) usage 0 ;;
  stop)         stop_container; exit 0 ;;
  status)       docker ps --filter "name=$CONTAINER" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'; exit 0 ;;
  -p)           PORT="${2:?missing port}"; shift 2 ;;
esac

SPEC="${1:?spec file required — run 'swagger-ui.sh --help'}"
[ -f "$SPEC" ] || { echo "File not found: $SPEC" >&2; exit 1; }

SPEC_ABS="$(readlink -f "$SPEC")"
SPEC_DIR="$(dirname "$SPEC_ABS")"
SPEC_FILE="$(basename "$SPEC_ABS")"

# Replace any existing instance so repeated runs "just work".
docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER" && docker rm -f "$CONTAINER" >/dev/null

docker run -d \
  --name "$CONTAINER" \
  -p "${PORT}:8080" \
  -e "SWAGGER_JSON=/spec/${SPEC_FILE}" \
  -v "${SPEC_DIR}:/spec:ro" \
  "$IMAGE" >/dev/null

# Wait briefly for the server to come up.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -sf -o /dev/null "http://localhost:${PORT}/"; then
    echo "Swagger UI: http://localhost:${PORT}/  (spec: ${SPEC_ABS})"
    echo "Stop with: swagger-ui.sh stop"
    exit 0
  fi
  sleep 0.5
done

echo "Container started but did not respond on :${PORT} yet. Check: docker logs $CONTAINER" >&2
exit 1
