#!/bin/sh
set -eu

# Shared finite-deploy helpers for Synology DSM Task Scheduler jobs.

SYN_DEPLOY_LOG_MAX_BYTES="${SYN_DEPLOY_LOG_MAX_BYTES:-2097152}"
SYN_DEPLOY_LOG_MAX_FILES="${SYN_DEPLOY_LOG_MAX_FILES:-3}"
SYN_DEPLOY_TIMEOUT_SECONDS="${SYN_DEPLOY_TIMEOUT_SECONDS:-900}"
SYN_DEPLOY_LOCK_TTL_SECONDS="${SYN_DEPLOY_LOCK_TTL_SECONDS:-3600}"
SYN_DEPLOY_LOCK_DIR=""
SYN_DEPLOY_LOG_DIR=""
SYN_DEPLOY_LOG_FILE=""
SYN_DEPLOY_DOCKER_BIN=""
SYN_DEPLOY_COMPOSE_BIN=""
SYN_DEPLOY_COMPOSE_KIND=""

synology_deploy_setup_path() {
  PATH="/usr/local/bin:/opt/bin:/usr/bin:/bin:/usr/syno/bin:/var/packages/ContainerManager/target/usr/bin:/volume1/@appstore/ContainerManager/usr/bin:/var/packages/Docker/target/usr/bin:/volume1/@appstore/Docker/usr/bin:/var/packages/Git/target/bin:/volume1/@appstore/Git/bin:$PATH"
  export PATH
}

synology_deploy_rotate_log() {
  file="$1"
  max_bytes="${2:-$SYN_DEPLOY_LOG_MAX_BYTES}"
  max_files="${3:-$SYN_DEPLOY_LOG_MAX_FILES}"

  [ -f "$file" ] || return 0

  bytes=$(wc -c < "$file" 2>/dev/null | tr -d ' ' || printf "0")
  case "$bytes" in
    "" | *[!0-9]* ) bytes=0 ;;
  esac

  [ "$bytes" -le "$max_bytes" ] && return 0

  idx="$max_files"
  while [ "$idx" -gt 1 ]; do
    prev=$((idx - 1))
    [ -f "$file.$prev" ] && mv "$file.$prev" "$file.$idx" 2>/dev/null || true
    idx="$prev"
  done

  mv "$file" "$file.1" 2>/dev/null || true
}

synology_deploy_set_log() {
  SYN_DEPLOY_LOG_DIR="$1"
  log_name="$2"
  mkdir -p "$SYN_DEPLOY_LOG_DIR"
  SYN_DEPLOY_LOG_FILE="$SYN_DEPLOY_LOG_DIR/$log_name"
  synology_deploy_rotate_log "$SYN_DEPLOY_LOG_FILE"
  export SYN_DEPLOY_LOG_DIR SYN_DEPLOY_LOG_FILE
}

synology_deploy_log() {
  mkdir -p "${SYN_DEPLOY_LOG_DIR:-/tmp}"
  if [ -n "${SYN_DEPLOY_LOG_FILE:-}" ]; then
    printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$SYN_DEPLOY_LOG_FILE"
  else
    printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
  fi
}

synology_deploy_fail() {
  synology_deploy_log "ERROR: $*"
  exit 1
}

synology_deploy_release_lock() {
  if [ -n "${SYN_DEPLOY_LOCK_DIR:-}" ] && [ -d "$SYN_DEPLOY_LOCK_DIR" ]; then
    owner_pid=$(cat "$SYN_DEPLOY_LOCK_DIR/pid" 2>/dev/null || true)
    if [ "$owner_pid" = "$$" ]; then
      rm -rf "$SYN_DEPLOY_LOCK_DIR"
    fi
  fi
}

synology_deploy_on_exit() {
  status=$?
  synology_deploy_release_lock
  return "$status"
}

synology_deploy_on_signal() {
  status=$?
  synology_deploy_release_lock
  exit "$status"
}

synology_deploy_acquire_lock() {
  lock_dir="$1"
  lock_name="$2"
  mkdir -p "$(dirname "$lock_dir")"

  if mkdir "$lock_dir" 2>/dev/null; then
    SYN_DEPLOY_LOCK_DIR="$lock_dir"
    printf "%s\n" "$$" > "$lock_dir/pid"
    date '+%s' > "$lock_dir/started_at" 2>/dev/null || true
    printf "%s\n" "$lock_name" > "$lock_dir/name"
    trap synology_deploy_on_exit EXIT
    trap synology_deploy_on_signal HUP INT TERM
    synology_deploy_log "Acquired deploy lock: $lock_dir"
    return 0
  fi

  owner_pid=$(cat "$lock_dir/pid" 2>/dev/null || true)
  if [ -n "$owner_pid" ] && kill -0 "$owner_pid" 2>/dev/null; then
    synology_deploy_log "Another $lock_name job is already running. lock=$lock_dir pid=$owner_pid"
    exit 75
  fi

  synology_deploy_log "Removing stale deploy lock: $lock_dir"
  rm -rf "$lock_dir"

  if mkdir "$lock_dir" 2>/dev/null; then
    SYN_DEPLOY_LOCK_DIR="$lock_dir"
    printf "%s\n" "$$" > "$lock_dir/pid"
    date '+%s' > "$lock_dir/started_at" 2>/dev/null || true
    printf "%s\n" "$lock_name" > "$lock_dir/name"
    trap synology_deploy_on_exit EXIT
    trap synology_deploy_on_signal HUP INT TERM
    synology_deploy_log "Acquired deploy lock after stale cleanup: $lock_dir"
    return 0
  fi

  synology_deploy_fail "Could not acquire deploy lock: $lock_dir"
}

synology_deploy_find_docker() {
  if [ -n "${DOCKER_BIN:-}" ] && [ -x "$DOCKER_BIN" ]; then
    printf "%s\n" "$DOCKER_BIN"
    return 0
  fi

  for candidate in \
    /usr/local/bin/docker \
    /usr/bin/docker \
    /bin/docker \
    /var/packages/ContainerManager/target/usr/bin/docker \
    /volume1/@appstore/ContainerManager/usr/bin/docker \
    /var/packages/Docker/target/usr/bin/docker \
    /volume1/@appstore/Docker/usr/bin/docker
  do
    if [ -x "$candidate" ]; then
      printf "%s\n" "$candidate"
      return 0
    fi
  done

  command -v docker 2>/dev/null || return 1
}

synology_deploy_find_docker_compose() {
  if [ -n "${DOCKER_COMPOSE_BIN:-}" ] && [ -x "$DOCKER_COMPOSE_BIN" ]; then
    printf "%s\n" "$DOCKER_COMPOSE_BIN"
    return 0
  fi

  for candidate in \
    /usr/local/bin/docker-compose \
    /usr/bin/docker-compose \
    /bin/docker-compose \
    /var/packages/ContainerManager/target/usr/bin/docker-compose \
    /volume1/@appstore/ContainerManager/usr/bin/docker-compose \
    /var/packages/Docker/target/usr/bin/docker-compose \
    /volume1/@appstore/Docker/usr/bin/docker-compose
  do
    if [ -x "$candidate" ]; then
      printf "%s\n" "$candidate"
      return 0
    fi
  done

  command -v docker-compose 2>/dev/null || return 1
}

synology_deploy_detect_compose() {
  SYN_DEPLOY_DOCKER_BIN=$(synology_deploy_find_docker) || synology_deploy_fail "Docker was not found. Install or enable Synology Container Manager."

  if "$SYN_DEPLOY_DOCKER_BIN" compose version >/dev/null 2>&1; then
    SYN_DEPLOY_COMPOSE_KIND="docker"
    SYN_DEPLOY_COMPOSE_BIN="$SYN_DEPLOY_DOCKER_BIN"
    export SYN_DEPLOY_DOCKER_BIN SYN_DEPLOY_COMPOSE_BIN SYN_DEPLOY_COMPOSE_KIND
    return 0
  fi

  SYN_DEPLOY_COMPOSE_BIN=$(synology_deploy_find_docker_compose) || synology_deploy_fail "Docker Compose was not found. Install Synology Container Manager or docker-compose."
  SYN_DEPLOY_COMPOSE_KIND="docker-compose"
  export SYN_DEPLOY_DOCKER_BIN SYN_DEPLOY_COMPOSE_BIN SYN_DEPLOY_COMPOSE_KIND
}

synology_deploy_compose() {
  [ -n "$SYN_DEPLOY_COMPOSE_KIND" ] || synology_deploy_detect_compose
  if [ "$SYN_DEPLOY_COMPOSE_KIND" = "docker" ]; then
    "$SYN_DEPLOY_DOCKER_BIN" compose "$@"
  else
    "$SYN_DEPLOY_COMPOSE_BIN" "$@"
  fi
}

synology_deploy_compose_runtime() {
  compose_file="$1"
  env_file="$2"
  shift 2
  runtime_dir=$(dirname "$compose_file")

  [ -n "$SYN_DEPLOY_COMPOSE_KIND" ] || synology_deploy_detect_compose

  if [ "$SYN_DEPLOY_COMPOSE_KIND" = "docker" ]; then
    "$SYN_DEPLOY_DOCKER_BIN" compose -f "$compose_file" --env-file "$env_file" "$@"
    return
  fi

  if "$SYN_DEPLOY_COMPOSE_BIN" -f "$compose_file" --env-file "$env_file" "$@"; then
    return
  fi

  synology_deploy_log "docker-compose rejected --env-file or absolute runtime paths; retrying from $runtime_dir without --env-file."
  (cd "$runtime_dir" && "$SYN_DEPLOY_COMPOSE_BIN" -f docker-compose.yml "$@")
}

synology_deploy_with_timeout() {
  seconds="$1"
  shift

  flag="/tmp/synology-deploy-timeout-$$-$(date '+%s')"
  "$@" &
  child_pid=$!
  (
    sleep "$seconds"
    if kill -0 "$child_pid" 2>/dev/null; then
      printf "timeout\n" > "$flag"
      kill -TERM "$child_pid" 2>/dev/null || true
      sleep 10
      kill -KILL "$child_pid" 2>/dev/null || true
    fi
  ) &
  watcher_pid=$!

  set +e
  wait "$child_pid"
  status=$?
  set -e

  kill "$watcher_pid" 2>/dev/null || true
  wait "$watcher_pid" 2>/dev/null || true

  if [ -f "$flag" ]; then
    rm -f "$flag"
    return 124
  fi

  return "$status"
}

synology_deploy_run_with_timeout() {
  seconds="$1"
  shift
  tmp_log="${SYN_DEPLOY_LOG_DIR:-/tmp}/run-$$-$(date '+%s').log"
  synology_deploy_log "+ timeout ${seconds}s $*"

  if synology_deploy_with_timeout "$seconds" "$@" > "$tmp_log" 2>&1; then
    cat "$tmp_log" | tee -a "$SYN_DEPLOY_LOG_FILE" >/dev/null
    rm -f "$tmp_log"
    return 0
  fi

  status=$?
  cat "$tmp_log" | tee -a "$SYN_DEPLOY_LOG_FILE" >/dev/null
  rm -f "$tmp_log"

  if [ "$status" -eq 124 ]; then
    synology_deploy_log "Command timed out after ${seconds}s: $*"
  else
    synology_deploy_log "Command failed with exit $status: $*"
  fi

  return "$status"
}

synology_deploy_env_value() {
  key="$1"
  env_file="$2"
  sed -n "s/^${key}=//p" "$env_file" 2>/dev/null | tail -n 1 | sed "s/\r$//"
}

synology_deploy_http_status() {
  url="$1"
  output_file="$2"
  curl -k -sS --max-time 10 -o "$output_file" -w "%{http_code}" "$url" 2>/dev/null || printf "000"
}

synology_deploy_wait_http() {
  url="$1"
  ok_statuses="$2"
  max_seconds="$3"
  interval_seconds="${4:-2}"
  elapsed=0
  body_file="/tmp/synology-deploy-http-$$.out"
  status="000"

  command -v curl >/dev/null 2>&1 || synology_deploy_fail "curl was not found; cannot verify health endpoint."

  while [ "$elapsed" -lt "$max_seconds" ]; do
    status=$(synology_deploy_http_status "$url" "$body_file")
    case " $ok_statuses " in
      *" $status "* )
        rm -f "$body_file"
        synology_deploy_log "HTTP check passed: $url status=$status"
        return 0
        ;;
    esac
    sleep "$interval_seconds"
    elapsed=$((elapsed + interval_seconds))
  done

  if [ -f "$body_file" ]; then
    synology_deploy_log "Last HTTP body from $url:"
    sed -n '1,20p' "$body_file" | while IFS= read -r line; do
      synology_deploy_log "HEALTH: $line"
    done
    rm -f "$body_file"
  fi

  synology_deploy_fail "HTTP check failed: $url last_status=$status timeout=${max_seconds}s"
}

synology_deploy_wait_container_healthy() {
  container_name="$1"
  max_seconds="$2"
  interval_seconds="${3:-3}"
  elapsed=0

  while [ "$elapsed" -lt "$max_seconds" ]; do
    state=$("$SYN_DEPLOY_DOCKER_BIN" inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null || true)
    health=$("$SYN_DEPLOY_DOCKER_BIN" inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container_name" 2>/dev/null || true)

    if [ "$state" = "running" ] && { [ "$health" = "healthy" ] || [ "$health" = "none" ]; }; then
      synology_deploy_log "Container state passed: $container_name state=$state health=$health"
      return 0
    fi

    if [ "$state" = "exited" ] || [ "$state" = "dead" ]; then
      synology_deploy_log "Container exited during health wait: $container_name state=$state health=$health"
      "$SYN_DEPLOY_DOCKER_BIN" logs --tail 120 "$container_name" 2>&1 | while IFS= read -r line; do
        synology_deploy_log "DOCKER: $line"
      done
      synology_deploy_fail "Container is not running: $container_name"
    fi

    sleep "$interval_seconds"
    elapsed=$((elapsed + interval_seconds))
  done

  synology_deploy_fail "Container did not become healthy: $container_name state=${state:-unknown} health=${health:-unknown}"
}

synology_deploy_tail_container_logs() {
  container_name="$1"
  lines="${2:-120}"
  [ -n "$SYN_DEPLOY_DOCKER_BIN" ] || synology_deploy_detect_compose
  synology_deploy_log "Recent $container_name logs:"
  "$SYN_DEPLOY_DOCKER_BIN" logs --tail "$lines" "$container_name" 2>&1 | while IFS= read -r line; do
    synology_deploy_log "DOCKER: $line"
  done || true
}
