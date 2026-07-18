#!/bin/sh
set -eu

APP_DIR="${APP_DIR:-/volume1/docker/wiregene-portal}"
LOG_DIR="${LOG_DIR:-$APP_DIR/.logs}"
LOG_FILE="$LOG_DIR/web-start-disabled.log"

mkdir -p "$LOG_DIR"
printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "ERROR: scripts/synology-web-start.sh is disabled." | tee -a "$LOG_FILE" >&2
printf "%s\n" "Use scripts/synology-update-portal.sh for DSM deployment. It pulls a prebuilt image and runs docker compose up -d --remove-orphans." | tee -a "$LOG_FILE" >&2
printf "%s\n" "This disabled legacy entrypoint intentionally does not run npm install, npm run build, npm start, next dev, docker logs -f, tail -f, docker rm -f, or prune commands." | tee -a "$LOG_FILE" >&2
exit 2
