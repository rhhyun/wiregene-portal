#!/bin/sh
set -eu

APP_DIR="${APP_DIR:-/volume1/docker/wiregene-portal}"
RUNTIME_DIR="${PORTAL_RUNTIME_DIR:-/volume1/docker/portal}"
LOG_DIR="${PORTAL_LOG_DIR:-$RUNTIME_DIR/logs}"
LOG_FILE="$LOG_DIR/portal-account-google-drive-backup.log"

log() {
  mkdir -p "$LOG_DIR"
  printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

fail() {
  log "ERROR: $*"
  exit 1
}

compose_runtime() {
  if docker compose version >/dev/null 2>&1; then
    docker compose -f "$RUNTIME_DIR/docker-compose.yml" --env-file "$RUNTIME_DIR/.env" "$@"
    return
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    if docker-compose -f "$RUNTIME_DIR/docker-compose.yml" --env-file "$RUNTIME_DIR/.env" "$@"; then
      return
    fi

    log "docker-compose rejected --env-file; retrying from $RUNTIME_DIR without --env-file."
    (cd "$RUNTIME_DIR" && docker-compose -f docker-compose.yml "$@")
    return
  fi

  fail "Docker Compose was not found. Install Synology Container Manager or docker-compose."
}

main() {
  log "Wiregene Portal account Google Drive backup requested."
  [ -d "$APP_DIR" ] || fail "APP_DIR was not found: $APP_DIR"
  [ -f "$RUNTIME_DIR/.env" ] || fail "Runtime env was not found: $RUNTIME_DIR/.env"
  [ -f "$RUNTIME_DIR/docker-compose.yml" ] || fail "Runtime compose file was not found: $RUNTIME_DIR/docker-compose.yml"

  compose_runtime run --rm --no-deps portal sh -lc 'npm run portal:backup-google-drive'
  log "Wiregene Portal account Google Drive backup completed."
}

main "$@"
