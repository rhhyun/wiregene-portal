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
  sed -n 's/^export const BRIEFING_VERSION[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$APP_DIR/src/lib/version.ts" | sed -n '1p'
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

check_public_portal_route() {
  skip_public_check="$(env_value SKIP_PUBLIC_PORTAL_ROUTE_CHECK || true)"
  if [ "${SKIP_PUBLIC_PORTAL_ROUTE_CHECK:-}" = "1" ] || [ "$skip_public_check" = "1" ]; then
    log "Skipping public portal route check because SKIP_PUBLIC_PORTAL_ROUTE_CHECK=1."
    return 0
  fi

  public_route_policy="$(env_value PUBLIC_PORTAL_ROUTE_POLICY || true)"
  [ -n "$public_route_policy" ] || public_route_policy="${PUBLIC_PORTAL_ROUTE_POLICY:-warn}"

  public_host="$(env_value PUBLIC_PORTAL_HOST || true)"
  [ -n "$public_host" ] || public_host="${PUBLIC_PORTAL_HOST:-portal.wiregene.com}"
  if [ -z "$public_host" ]; then
    log "Skipping public portal route check because PUBLIC_PORTAL_HOST is empty."
    return 0
  fi

  log "Checking public portal route at https://$public_host."
  public_headers="$(curl -k -sSI --max-time 15 "https://$public_host/" 2>&1 || true)"
  if [ -z "$public_headers" ]; then
    log "WARNING: Could not read public portal headers for https://$public_host."
    return 0
  fi

  printf "%s\n" "$public_headers" | sed -n '1,20p' | while IFS= read -r line; do
    log "PUBLIC: $line"
  done

  if printf "%s\n" "$public_headers" | grep -Eiq '^(server:[[:space:]]*Vercel|x-vercel-)'; then
    log "Public portal host https://$public_host is currently served by Vercel."
    log "If Portal is intentionally running on Vercel, this is expected; account storage must then use a valid Google Drive OAuth configuration on the Vercel project."
    log "If Portal is intended to run publicly from Synology, apply this route fix:"
    log "1. DSM Control Panel > Login Portal > Advanced > Reverse Proxy: source HTTPS $public_host:443 -> destination HTTP 127.0.0.1:3002."
    log "2. Router/firewall: forward external TCP 443 to the Synology NAS if the NAS is the public HTTPS endpoint."
    log "3. Cloudflare DNS: point $public_host to the Synology public endpoint, not Vercel 76.76.21.21."
    log "4. Only after the public header no longer contains Server: Vercel or X-Vercel-Id, remove the Vercel alias/domain binding for $public_host."
    log "5. Verify from a PC with: curl.exe -I https://$public_host/ ; the response must not contain Server: Vercel or X-Vercel-Id."
    log "Set PUBLIC_PORTAL_ROUTE_POLICY=synology in $RUNTIME_DIR/.env if this scheduler should fail whenever the public host is still Vercel."

    if [ "$public_route_policy" = "synology" ]; then
      fail "Public portal host https://$public_host is still served by Vercel, but PUBLIC_PORTAL_ROUTE_POLICY=synology requires public Synology routing."
    fi

    log "Continuing because PUBLIC_PORTAL_ROUTE_POLICY=$public_route_policy. Synology local app is healthy; public browser traffic still goes to Vercel."
    return 0
  fi

  log "Public portal route is not reporting Vercel headers."
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
  check_public_portal_route

  log_recent_container_output
  log "Wiregene Portal update completed successfully."
}

main "$@"
