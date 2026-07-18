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
synology_deploy_set_log "$LOG_DIR" "status.log"
synology_deploy_detect_compose

log() {
  synology_deploy_log "$*"
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

main() {
  status=0
  container_name="$(env_or_default CONTAINER_NAME wiregene-portal)"
  host_port="$(env_or_default HOST_PORT 3002)"
  health_url="$(env_or_default PORTAL_LOCAL_HEALTH_URL "http://127.0.0.1:$host_port/api/health")"
  lock_dir="${PORTAL_DEPLOY_LOCK_DIR:-$RUNTIME_DIR/.deploy.lock}"

  log "Wiregene Portal status check started."

  if [ -d "$lock_dir" ]; then
    owner_pid=$(cat "$lock_dir/pid" 2>/dev/null || true)
    if [ -n "$owner_pid" ] && kill -0 "$owner_pid" 2>/dev/null; then
      log "ERROR: deploy lock is still active. lock=$lock_dir pid=$owner_pid"
      status=75
    else
      log "WARNING: stale deploy lock exists. lock=$lock_dir"
    fi
  fi

  synology_deploy_run_with_timeout 30 synology_deploy_compose_runtime "$RUNTIME_DIR/docker-compose.yml" "$RUNTIME_DIR/.env" ps || status=1

  state=$("$SYN_DEPLOY_DOCKER_BIN" inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null || true)
  health=$("$SYN_DEPLOY_DOCKER_BIN" inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container_name" 2>/dev/null || true)
  log "Container state: name=$container_name state=${state:-missing} health=${health:-missing}"
  if [ "$state" != "running" ]; then
    status=1
  fi
  if [ "$health" != "healthy" ] && [ "$health" != "none" ]; then
    status=1
  fi

  if synology_deploy_wait_http "$health_url" "200" 20 2; then
    :
  else
    status=1
  fi

  leftovers="$(ps 2>/dev/null | grep -E 'synology-update-portal|synology-start-portal|docker logs -f|tail -f|npm run dev|next dev' | grep -v grep | grep -v synology-portal-status || true)"
  if [ -n "$leftovers" ]; then
    log "ERROR: possible leftover scheduler/development process found:"
    printf "%s\n" "$leftovers" | while IFS= read -r line; do
      log "PROCESS: $line"
    done
    status=1
  else
    log "No leftover deploy scheduler or dev-server process found."
  fi

  if [ "$status" -eq 0 ]; then
    log "Wiregene Portal status check passed."
  else
    log "Wiregene Portal status check failed with status=$status."
  fi
  exit "$status"
}

main "$@"
