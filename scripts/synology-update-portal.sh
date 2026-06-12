#!/bin/sh
set -eu

APP_DIR="${APP_DIR:-/volume1/docker/wiregene-portal}"
RUNTIME_DIR="${PORTAL_RUNTIME_DIR:-/volume1/docker/portal}"
LOG_DIR="${PORTAL_LOG_DIR:-$RUNTIME_DIR/logs}"
LOG_FILE="$LOG_DIR/update-$(date '+%Y%m%d-%H%M%S').log"

log() {
  mkdir -p "$LOG_DIR"
  printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

fail() {
  log "ERROR: $*"
  log_recent_container_output
  exit 1
}

run() {
  log "+ $*"
  tmp_log="$LOG_DIR/run-$$.log"
  if "$@" >"$tmp_log" 2>&1; then
    cat "$tmp_log" | tee -a "$LOG_FILE"
    rm -f "$tmp_log"
    return 0
  fi

  status="$?"
  cat "$tmp_log" | tee -a "$LOG_FILE"
  rm -f "$tmp_log"
  return "$status"
}

version_from_source() {
  sed -n 's/.*BRIEFING_VERSION = "\([^"]*\)".*/\1/p' "$APP_DIR/src/lib/version.ts" | head -n 1
}

env_value() {
  key="$1"
  sed -n "s/^${key}=//p" "$RUNTIME_DIR/.env" 2>/dev/null | tail -n 1 | sed "s/\r$//"
}

auth_pair() {
  auth_users="$(env_value APP_BASIC_AUTH_USERS)"
  if [ -n "$auth_users" ]; then
    printf "%s" "$auth_users" | cut -d, -f1
    return
  fi

  auth_user="$(env_value APP_BASIC_AUTH_USER)"
  auth_password="$(env_value APP_BASIC_AUTH_PASSWORD)"
  if [ -n "$auth_user" ] && [ -n "$auth_password" ]; then
    printf "%s:%s" "$auth_user" "$auth_password"
  fi
}

log_recent_container_output() {
  if command -v docker >/dev/null 2>&1; then
    log "Recent wiregene-portal logs:"
    docker logs --tail 120 wiregene-portal 2>&1 | tee -a "$LOG_FILE" || true
  fi
}

wait_for_local_http() {
  log "Waiting for local portal HTTP response on http://127.0.0.1:3002."
  i=0
  while [ "$i" -lt 60 ]; do
    status="$(curl -sS -o /tmp/wiregene-portal-http-check.html -w "%{http_code}" http://127.0.0.1:3002 2>/dev/null || true)"
    if [ "$status" = "200" ] || [ "$status" = "401" ]; then
      log "Local HTTP status is $status."
      return 0
    fi
    i=$((i + 1))
    sleep 2
  done

  fail "Portal did not become ready on local HTTP port 3002. Last status: ${status:-none}"
}

verify_page_version() {
  expected_version="$1"
  pair="$(auth_pair || true)"

  if [ -z "$pair" ]; then
    log "Skipping page version check because no Basic Auth credential was found in $RUNTIME_DIR/.env."
    return 0
  fi

  log "Checking rendered portal version. Expected Ver $expected_version."
  page="$(curl -fsS -u "$pair" http://127.0.0.1:3002 2>/dev/null || true)"
  rendered_version="$(printf "%s" "$page" | grep -o 'Ver [0-9][0-9.]*' | head -n 1 || true)"

  if [ "$rendered_version" != "Ver $expected_version" ]; then
    fail "Rendered version mismatch. Expected 'Ver $expected_version', got '${rendered_version:-none}'."
  fi

  log "Rendered version confirmed: $rendered_version"
}

main() {
  mkdir -p "$LOG_DIR"
  log "Wiregene Portal full update requested."
  log "Log file: $LOG_FILE"

  [ -d "$APP_DIR/.git" ] || fail "Git checkout was not found at APP_DIR=$APP_DIR"
  cd "$APP_DIR"

  log "Updating source checkout."
  run git status --short --branch
  run git pull --ff-only origin main
  run git log -1 --oneline

  expected_version="$(version_from_source)"
  [ -n "$expected_version" ] || fail "Could not read BRIEFING_VERSION from src/lib/version.ts."
  log "Source version: Ver $expected_version"

  run /bin/sh "$APP_DIR/scripts/synology-start-portal.sh"

  log "Container status:"
  docker ps --filter name=wiregene-portal 2>&1 | tee -a "$LOG_FILE" || true

  wait_for_local_http
  verify_page_version "$expected_version"

  log_recent_container_output
  log "Wiregene Portal update completed successfully."
}

main "$@"
