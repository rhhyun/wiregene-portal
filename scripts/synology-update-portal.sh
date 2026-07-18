#!/bin/sh
set -eu

APP_DIR="${APP_DIR:-/volume1/docker/wiregene-portal}"
RUNTIME_DIR="${PORTAL_RUNTIME_DIR:-/volume1/docker/portal}"
LOG_DIR="${PORTAL_LOG_DIR:-$RUNTIME_DIR/logs}"
COMMON_SCRIPT="$APP_DIR/scripts/synology-deploy-common.sh"

[ -f "$COMMON_SCRIPT" ] || {
  printf "%s\n" "ERROR: common deploy helper was not found: $COMMON_SCRIPT" >&2
  exit 1
}

. "$COMMON_SCRIPT"
synology_deploy_setup_path
synology_deploy_set_log "$LOG_DIR" "update.log"

log() {
  synology_deploy_log "$*"
}

fail() {
  log "ERROR: $*"
  log_recent_container_output
  exit 1
}

version_from_source() {
  sed -n 's/^export const BRIEFING_VERSION[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$APP_DIR/src/lib/version.ts" | sed -n '1p'
}

env_value() {
  key="$1"
  synology_deploy_env_value "$key" "$RUNTIME_DIR/.env"
}

env_or_default() {
  key="$1"
  default_value="$2"
  current="$(env_value "$key" || true)"
  [ -n "$current" ] || current="$default_value"
  printf "%s" "$current"
}

auth_pair() {
  auth_users="$(env_value APP_BASIC_AUTH_USERS || true)"
  if [ -n "$auth_users" ]; then
    printf "%s" "$auth_users" | cut -d, -f1
    return
  fi

  auth_user="$(env_value APP_BASIC_AUTH_USER || true)"
  auth_password="$(env_value APP_BASIC_AUTH_PASSWORD || true)"
  if [ -n "$auth_user" ] && [ -n "$auth_password" ]; then
    printf "%s:%s" "$auth_user" "$auth_password"
  fi
}

log_recent_container_output() {
  if [ -n "${SYN_DEPLOY_DOCKER_BIN:-}" ] || command -v docker >/dev/null 2>&1; then
    synology_deploy_tail_container_logs "wiregene-portal" 120
  fi
}

wait_for_local_http() {
  host_port="$(env_or_default HOST_PORT 3002)"
  health_timeout="$(env_or_default PORTAL_HEALTH_TIMEOUT_SECONDS 120)"
  health_url="$(env_or_default PORTAL_LOCAL_HEALTH_URL "http://127.0.0.1:$host_port/api/health")"
  root_url="http://127.0.0.1:$host_port/"

  log "Waiting for Portal health endpoint: $health_url"
  synology_deploy_wait_http "$health_url" "200" "$health_timeout" 2

  log "Checking local Portal root route: $root_url"
  synology_deploy_wait_http "$root_url" "200 401" 30 2
}

verify_page_version() {
  expected_version="$1"
  host_port="$(env_or_default HOST_PORT 3002)"
  pair="$(auth_pair || true)"

  if [ -z "$pair" ]; then
    log "Skipping page version check because no Basic Auth credential was found in $RUNTIME_DIR/.env."
    return 0
  fi

  log "Checking rendered portal version. Expected Ver $expected_version."
  page="$(curl -fsS --max-time 15 -u "$pair" "http://127.0.0.1:$host_port" 2>/dev/null || true)"
  rendered_version="$(printf "%s" "$page" | grep -o 'Ver [0-9][0-9.]*' | head -n 1 || true)"

  if [ "$rendered_version" != "Ver $expected_version" ]; then
    fail "Rendered version mismatch. Expected 'Ver $expected_version', got '${rendered_version:-none}'. The GHCR image may not have been built for the current source commit yet."
  fi

  log "Rendered version confirmed: $rendered_version"
}

check_public_portal_route() {
  skip_public_check="$(env_value SKIP_PUBLIC_PORTAL_ROUTE_CHECK || true)"
  if [ "${SKIP_PUBLIC_PORTAL_ROUTE_CHECK:-}" = "1" ] || [ "$skip_public_check" = "1" ]; then
    fail "SKIP_PUBLIC_PORTAL_ROUTE_CHECK=1 is no longer supported. Use the explicit vercel-emergency policy for a temporary break-glass route."
  fi

  public_route_policy="$(env_value PUBLIC_PORTAL_ROUTE_POLICY || true)"
  [ -n "$public_route_policy" ] || public_route_policy="${PUBLIC_PORTAL_ROUTE_POLICY:-synology}"

  case "$public_route_policy" in
    synology)
      ;;
    vercel-emergency)
      log "WARNING: PUBLIC_PORTAL_ROUTE_POLICY=vercel-emergency permits a temporary public Vercel route. Account management remains read-only there."
      ;;
    warn)
      log "WARNING: Legacy PUBLIC_PORTAL_ROUTE_POLICY=warn is no longer permissive; enforcing synology policy."
      public_route_policy="synology"
      ;;
    *)
      fail "Unsupported PUBLIC_PORTAL_ROUTE_POLICY=$public_route_policy. Use synology or the explicit break-glass value vercel-emergency."
      ;;
  esac

  public_host="$(env_value PUBLIC_PORTAL_HOST || true)"
  [ -n "$public_host" ] || public_host="${PUBLIC_PORTAL_HOST:-portal.wiregene.com}"
  if [ -z "$public_host" ]; then
    log "Skipping public portal route check because PUBLIC_PORTAL_HOST is empty."
    return 0
  fi

  log "Checking public portal route at https://$public_host."
  public_headers="$(curl -k -sSI --max-time 15 "https://$public_host/" 2>&1 || true)"
  if [ -z "$public_headers" ]; then
    if [ "$public_route_policy" = "vercel-emergency" ]; then
      log "WARNING: Could not read public portal headers for https://$public_host during emergency Vercel mode."
      return 0
    fi
    fail "Could not read public portal headers for https://$public_host; Synology routing cannot be verified."
  fi

  printf "%s\n" "$public_headers" | sed -n '1,20p' | while IFS= read -r line; do
    log "PUBLIC: $line"
  done

  if printf "%s\n" "$public_headers" | grep -Eiq '^(server:[[:space:]]*Vercel|x-vercel-)'; then
    log "Public portal host https://$public_host is currently served by Vercel."
    log "Portal account management cannot write while public traffic is served by Vercel."
    log "If Portal is intended to run publicly from Synology, apply this route fix:"
    log "1. DSM Control Panel > Login Portal > Advanced > Reverse Proxy: source HTTPS $public_host:443 -> destination HTTP 127.0.0.1:3002."
    log "2. Router/firewall: forward external TCP 443 to the Synology NAS if the NAS is the public HTTPS endpoint."
    log "3. Cloudflare DNS: point $public_host to the Synology public endpoint, not Vercel 76.76.21.21."
    log "4. Only after the public header no longer contains Server: Vercel or X-Vercel-Id, remove the Vercel alias/domain binding for $public_host."
    log "5. Verify from a PC with: curl.exe -I https://$public_host/ ; the response must not contain Server: Vercel or X-Vercel-Id."
    if [ "$public_route_policy" = "vercel-emergency" ]; then
      log "WARNING: Continuing only because PUBLIC_PORTAL_ROUTE_POLICY=vercel-emergency."
      return 0
    fi

    fail "Public portal host https://$public_host is still served by Vercel; production account management requires public Synology routing."
  fi

  log "Public portal route is not reporting Vercel headers."
}

main() {
  mkdir -p "$RUNTIME_DIR" "$LOG_DIR"
  deploy_timeout="${PORTAL_DEPLOY_TIMEOUT_SECONDS:-$SYN_DEPLOY_TIMEOUT_SECONDS}"

  synology_deploy_acquire_lock "${PORTAL_DEPLOY_LOCK_DIR:-$RUNTIME_DIR/.deploy.lock}" "wiregene-portal-deploy"
  synology_deploy_detect_compose

  log "Wiregene Portal finite update requested."
  log "Max scheduler runtime: ${deploy_timeout}s"
  log "Log file: $SYN_DEPLOY_LOG_FILE"

  [ -d "$APP_DIR/.git" ] || fail "Git checkout was not found at APP_DIR=$APP_DIR"
  cd "$APP_DIR"

  log "Updating source checkout."
  synology_deploy_run_with_timeout 60 git status --short --branch || fail "git status failed."
  synology_deploy_run_with_timeout 180 git pull --ff-only origin main || fail "git pull failed."
  synology_deploy_run_with_timeout 30 git log -1 --oneline || fail "git log failed."

  expected_version="$(version_from_source)"
  [ -n "$expected_version" ] || fail "Could not read BRIEFING_VERSION from src/lib/version.ts."
  log "Source version: Ver $expected_version"

  PORTAL_DEPLOY_LOCK_HELD=1
  export PORTAL_DEPLOY_LOCK_HELD
  synology_deploy_run_with_timeout "$deploy_timeout" /bin/sh "$APP_DIR/scripts/synology-start-portal.sh" || fail "Portal start failed."

  wait_for_local_http
  verify_page_version "$expected_version"
  check_public_portal_route

  synology_deploy_run_with_timeout 30 "$SYN_DEPLOY_DOCKER_BIN" ps --filter name=wiregene-portal || true
  log_recent_container_output
  log "Wiregene Portal update completed successfully."
}

if [ "${PORTAL_ROUTE_CHECK_ONLY:-}" = "1" ]; then
  mkdir -p "$LOG_DIR"
  log "Wiregene Portal public route diagnostic requested."
  check_public_portal_route
  log "Wiregene Portal public route diagnostic passed."
  exit 0
fi

main "$@"
