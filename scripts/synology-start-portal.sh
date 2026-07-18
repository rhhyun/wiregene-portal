#!/bin/sh
set -eu

APP_DIR="${APP_DIR:-/volume1/docker/wiregene-portal}"
RUNTIME_DIR="${PORTAL_RUNTIME_DIR:-/volume1/docker/portal}"
PACKAGE_DIR="$APP_DIR/synology/docker/portal"
LOG_DIR="${PORTAL_LOG_DIR:-$RUNTIME_DIR/logs}"
COMMON_SCRIPT="$APP_DIR/scripts/synology-deploy-common.sh"

[ -f "$COMMON_SCRIPT" ] || {
  printf "%s\n" "ERROR: common deploy helper was not found: $COMMON_SCRIPT" >&2
  exit 1
}

. "$COMMON_SCRIPT"
synology_deploy_setup_path
synology_deploy_set_log "$LOG_DIR" "scheduler-start.log"

log() {
  synology_deploy_log "$*"
}

fail() {
  log "ERROR: $*"
  if [ -n "${SYN_DEPLOY_DOCKER_BIN:-}" ]; then
    synology_deploy_tail_container_logs "${CONTAINER_NAME:-wiregene-portal}" 120
  fi
  exit 1
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

verify_account_storage_volume() {
  storage_probe_timeout="$(env_or_default PORTAL_STORAGE_PROBE_TIMEOUT_SECONDS 60)"
  log "Verifying Portal account storage volume with create, rename, and delete operations."
  synology_deploy_run_with_timeout "$storage_probe_timeout" synology_deploy_compose_runtime "$RUNTIME_DIR/docker-compose.yml" "$RUNTIME_DIR/.env" run --rm --no-deps portal sh -lc '
    set -eu
    directory=/app/.data/portal
    temporary="$directory/.portal-storage-probe-$$.tmp"
    completed="$directory/.portal-storage-probe-$$.ok"
    mkdir -p "$directory"
    trap '\''rm -f "$temporary" "$completed"'\'' EXIT HUP INT TERM
    printf "%s\n" "portal-storage-probe" > "$temporary"
    mv "$temporary" "$completed"
    test -s "$completed"
    rm -f "$completed"
    trap - EXIT HUP INT TERM
  ' || fail "Portal account storage volume probe failed."
  log "Portal account storage volume is writable."
}

prepare_runtime() {
  [ -f "$APP_DIR/package.json" ] || fail "Shared app checkout was not found at APP_DIR=$APP_DIR"
  [ -d "$PACKAGE_DIR" ] || fail "Synology package directory was not found: $PACKAGE_DIR"

  mkdir -p "$RUNTIME_DIR" "$LOG_DIR" "$RUNTIME_DIR/data"
  cp "$PACKAGE_DIR/docker-compose.yml" "$RUNTIME_DIR/docker-compose.yml"
  cp "$PACKAGE_DIR/.env.example" "$RUNTIME_DIR/.env.example"
  cp "$PACKAGE_DIR/README.md" "$RUNTIME_DIR/README.md"

  if [ ! -f "$RUNTIME_DIR/.env" ]; then
    cp "$RUNTIME_DIR/.env.example" "$RUNTIME_DIR/.env"
    fail "Created $RUNTIME_DIR/.env from .env.example. Run $APP_DIR/scripts/synology-migrate-auth-env.sh to copy existing auth values without printing passwords, or fill auth values manually, then run this script again."
  fi
}

warn_unexpected_value() {
  key="$1"
  expected="$2"
  value=$(env_value "$key")
  if [ -n "$value" ] && [ "$value" != "$expected" ]; then
    log "WARNING: $key is '$value' in $RUNTIME_DIR/.env, expected '$expected'."
  fi
}

warn_runtime_env() {
  auth_user=$(env_value APP_BASIC_AUTH_USER)
  auth_password=$(env_value APP_BASIC_AUTH_PASSWORD)
  auth_users=$(env_value APP_BASIC_AUTH_USERS)
  admin_emails=$(env_value WIREGENE_ADMIN_EMAILS)
  admin_users=$(env_value APP_ADMIN_USERS)
  admin_user=$(env_value APP_ADMIN_USER)
  portal_image=$(env_value PORTAL_IMAGE)

  if [ -z "$auth_users" ] && { [ -z "$auth_user" ] || [ -z "$auth_password" ]; }; then
    fail "No complete Basic Auth credential found in $RUNTIME_DIR/.env. Run $APP_DIR/scripts/synology-migrate-auth-env.sh or set APP_BASIC_AUTH_USERS / APP_BASIC_AUTH_USER + APP_BASIC_AUTH_PASSWORD."
  fi

  if [ -z "$admin_emails" ] && [ -z "$admin_users" ] && [ -z "$admin_user" ]; then
    log "WARNING: No admin key found in $RUNTIME_DIR/.env. Set WIREGENE_ADMIN_EMAILS or APP_ADMIN_USERS if an admin badge/permission list is required."
  fi

  if [ -z "$portal_image" ]; then
    log "WARNING: PORTAL_IMAGE is empty in $RUNTIME_DIR/.env. Compose will use ghcr.io/rhhyun/wiregene-portal:latest."
  fi

  warn_unexpected_value APP_SOURCE_DIR "$APP_DIR"
  warn_unexpected_value HOST_PORT "3002"
  warn_unexpected_value CONTAINER_NAME "wiregene-portal"
  warn_unexpected_value WIREGENE_APP_MODE "portal"
}

validate_compose_config() {
  synology_deploy_run_with_timeout 60 synology_deploy_compose_runtime "$RUNTIME_DIR/docker-compose.yml" "$RUNTIME_DIR/.env" config >/dev/null || fail "Docker Compose could not read $RUNTIME_DIR/docker-compose.yml."
}

start_service() {
  pull_timeout="$(env_or_default PORTAL_COMPOSE_PULL_TIMEOUT_SECONDS 300)"
  up_timeout="$(env_or_default PORTAL_COMPOSE_UP_TIMEOUT_SECONDS 300)"
  health_timeout="$(env_or_default PORTAL_HEALTH_TIMEOUT_SECONDS 120)"
  container_name="$(env_or_default CONTAINER_NAME wiregene-portal)"
  host_port="$(env_or_default HOST_PORT 3002)"
  health_url="$(env_or_default PORTAL_LOCAL_HEALTH_URL "http://127.0.0.1:$host_port/api/health")"

  log "Pulling prebuilt Portal image."
  synology_deploy_run_with_timeout "$pull_timeout" synology_deploy_compose_runtime "$RUNTIME_DIR/docker-compose.yml" "$RUNTIME_DIR/.env" pull portal || fail "Docker image pull failed. Existing running container and volumes were not removed."

  verify_account_storage_volume

  log "Starting Portal with docker compose up -d --remove-orphans."
  synology_deploy_run_with_timeout "$up_timeout" synology_deploy_compose_runtime "$RUNTIME_DIR/docker-compose.yml" "$RUNTIME_DIR/.env" up -d --remove-orphans || fail "Docker Compose up failed. Existing persistent volumes were not removed."

  synology_deploy_wait_container_healthy "$container_name" "$health_timeout" 3
  synology_deploy_wait_http "$health_url" "200" "$health_timeout" 2
  synology_deploy_run_with_timeout 30 synology_deploy_compose_runtime "$RUNTIME_DIR/docker-compose.yml" "$RUNTIME_DIR/.env" ps || true
}

main() {
  if [ "${PORTAL_DEPLOY_LOCK_HELD:-}" != "1" ]; then
    synology_deploy_acquire_lock "${PORTAL_DEPLOY_LOCK_DIR:-$RUNTIME_DIR/.deploy.lock}" "wiregene-portal-start"
  fi

  log "Wiregene Portal DSM scheduler start requested."
  prepare_runtime
  warn_runtime_env
  synology_deploy_detect_compose
  validate_compose_config
  start_service
  log "Wiregene Portal start completed."
}

main "$@"
