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
synology_deploy_set_log "$LOG_DIR" "portal-account-google-drive-backup.log"

log() {
  synology_deploy_log "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

main() {
  backup_timeout="${PORTAL_ACCOUNT_BACKUP_TIMEOUT_SECONDS:-600}"
  synology_deploy_acquire_lock "${PORTAL_ACCOUNT_BACKUP_LOCK_DIR:-$RUNTIME_DIR/.backup.lock}" "wiregene-portal-account-backup"
  synology_deploy_detect_compose

  log "Wiregene Portal account Google Drive backup requested."
  [ -d "$APP_DIR" ] || fail "APP_DIR was not found: $APP_DIR"
  [ -f "$RUNTIME_DIR/.env" ] || fail "Runtime env was not found: $RUNTIME_DIR/.env"
  [ -f "$RUNTIME_DIR/docker-compose.yml" ] || fail "Runtime compose file was not found: $RUNTIME_DIR/docker-compose.yml"

  synology_deploy_run_with_timeout "$backup_timeout" synology_deploy_compose_runtime "$RUNTIME_DIR/docker-compose.yml" "$RUNTIME_DIR/.env" run --rm --no-deps portal npm run portal:backup-google-drive || fail "Portal account Google Drive backup failed."
  log "Wiregene Portal account Google Drive backup completed."
}

main "$@"
