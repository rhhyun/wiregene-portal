#!/bin/sh
set -eu

BASE_DIR="${BASE_DIR:-/volume1/docker}"
PORTAL_SOURCE_DIR="${PORTAL_SOURCE_DIR:-$BASE_DIR/wiregene-portal}"
PORTAL_RUNTIME_DIR="${PORTAL_RUNTIME_DIR:-$BASE_DIR/portal}"
PORTAL_REPO_URL="${PORTAL_REPO_URL:-https://github.com/rhhyun/wiregene-portal.git}"
IDENTITY_USERNAME="${IDENTITY_USERNAME:-rhhyun}"
LEGACY_SEARCH_USERNAME="${LEGACY_SEARCH_USERNAME:-wiregene}"
PORTAL_AUTH_CHECK_URL="${PORTAL_AUTH_CHECK_URL:-https://portal.wiregene.com/api/auth/check}"
AUTO_START="${AUTO_START:-true}"

LOG_DIR="${PORTAL_RUNTIME_DIR}/logs"
LOG_FILE="${LOG_DIR}/identity-auto-config.log"
LOCK_DIR="${PORTAL_RUNTIME_DIR}/.identity.lock"
LOG_MAX_BYTES="${LOG_MAX_BYTES:-2097152}"
LOG_MAX_FILES="${LOG_MAX_FILES:-3}"

PATH="/usr/local/bin:/opt/bin:/usr/bin:/bin:/usr/syno/bin:/var/packages/ContainerManager/target/usr/bin:/volume1/@appstore/ContainerManager/usr/bin:/var/packages/Docker/target/usr/bin:/volume1/@appstore/Docker/usr/bin:/var/packages/Git/target/bin:/volume1/@appstore/Git/bin:$PATH"
export PATH

rotate_log() {
  [ -f "$LOG_FILE" ] || return 0
  bytes=$(wc -c < "$LOG_FILE" 2>/dev/null | tr -d ' ' || printf "0")
  case "$bytes" in
    "" | *[!0-9]* ) bytes=0 ;;
  esac
  [ "$bytes" -le "$LOG_MAX_BYTES" ] && return 0

  idx="$LOG_MAX_FILES"
  while [ "$idx" -gt 1 ]; do
    prev=$((idx - 1))
    [ -f "$LOG_FILE.$prev" ] && mv "$LOG_FILE.$prev" "$LOG_FILE.$idx" 2>/dev/null || true
    idx="$prev"
  done
  mv "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null || true
}

cleanup_lock() {
  if [ -d "$LOCK_DIR" ]; then
    owner_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
    if [ "$owner_pid" = "$$" ]; then
      rm -rf "$LOCK_DIR"
    fi
  fi
}

on_signal() {
  cleanup_lock
  exit 130
}

acquire_lock() {
  mkdir -p "$PORTAL_RUNTIME_DIR"
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf "%s\n" "$$" > "$LOCK_DIR/pid"
    date '+%s' > "$LOCK_DIR/started_at" 2>/dev/null || true
    trap cleanup_lock EXIT
    trap on_signal HUP INT TERM
    return 0
  fi

  owner_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
  if [ -n "$owner_pid" ] && kill -0 "$owner_pid" 2>/dev/null; then
    printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "Another identity auto-config job is already running. lock=$LOCK_DIR pid=$owner_pid" | tee -a "$LOG_FILE" >&2
    exit 75
  fi

  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR" || fail "Could not acquire lock: $LOCK_DIR"
  printf "%s\n" "$$" > "$LOCK_DIR/pid"
  date '+%s' > "$LOCK_DIR/started_at" 2>/dev/null || true
  trap cleanup_lock EXIT
  trap on_signal HUP INT TERM
}

log() {
  mkdir -p "$LOG_DIR"
  rotate_log
  printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE" >&2
}

fail() {
  log "ERROR: $*"
  exit 1
}

compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    fail "Docker Compose was not found."
  fi
}

compose_up() {
  compose_file="$1"
  env_file="$2"
  runtime_dir=$(dirname "$compose_file")

  if docker compose version >/dev/null 2>&1; then
    docker compose -f "$compose_file" --env-file "$env_file" up -d --remove-orphans
    return
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    if docker-compose -f "$compose_file" --env-file "$env_file" up -d --remove-orphans; then
      return
    fi
    log "docker-compose rejected --env-file; retrying from $runtime_dir."
    (cd "$runtime_dir" && docker-compose -f docker-compose.yml up -d --remove-orphans)
    return
  fi

  fail "Docker Compose was not found."
}

ensure_repo() {
  mkdir -p "$BASE_DIR"

  if [ -d "$PORTAL_SOURCE_DIR/.git" ]; then
    log "Updating portal source checkout at $PORTAL_SOURCE_DIR."
    git -C "$PORTAL_SOURCE_DIR" pull --ff-only origin main || fail "git pull failed; refusing to continue with stale checkout."
    return
  fi

  if [ -e "$PORTAL_SOURCE_DIR" ]; then
    fail "$PORTAL_SOURCE_DIR exists but is not a Git checkout. Move it aside or set PORTAL_SOURCE_DIR."
  fi

  log "Cloning portal source into $PORTAL_SOURCE_DIR."
  git clone "$PORTAL_REPO_URL" "$PORTAL_SOURCE_DIR"
}

ensure_portal_env() {
  mkdir -p "$PORTAL_RUNTIME_DIR" "$LOG_DIR" "$PORTAL_RUNTIME_DIR/data"

  if [ ! -f "$PORTAL_RUNTIME_DIR/.env" ]; then
    if [ -f "$PORTAL_SOURCE_DIR/synology/docker/portal/.env.example" ]; then
      cp "$PORTAL_SOURCE_DIR/synology/docker/portal/.env.example" "$PORTAL_RUNTIME_DIR/.env"
      log "Created $PORTAL_RUNTIME_DIR/.env from portal package example."
    else
      cat > "$PORTAL_RUNTIME_DIR/.env" <<EOF
APP_SOURCE_DIR=$PORTAL_SOURCE_DIR
PORTAL_IMAGE=ghcr.io/rhhyun/wiregene-portal:latest
HOST_PORT=3002
CONTAINER_NAME=wiregene-portal
PORTAL_DEPLOY_TIMEOUT_SECONDS=900
PORTAL_COMPOSE_PULL_TIMEOUT_SECONDS=300
PORTAL_COMPOSE_UP_TIMEOUT_SECONDS=300
PORTAL_HEALTH_TIMEOUT_SECONDS=120
PORTAL_LOCAL_HEALTH_URL=http://127.0.0.1:3002/api/health

APP_BASE_URL=https://portal.wiregene.com
PUBLIC_PORTAL_HOST=portal.wiregene.com
PUBLIC_PORTAL_ROUTE_POLICY=synology
WIREGENE_APP_MODE=portal

APP_BASIC_AUTH_USER=
APP_BASIC_AUTH_PASSWORD=
APP_BASIC_AUTH_USERS=
APP_BASIC_AUTH_SITE_ACCESS=wiregene=search
WIREGENE_ADMIN_EMAILS=
PORTAL_AUTH_CHECK_SECRET=
WIREGENE_SUBSITE_ACCOUNTS=

REPORT_STORAGE_BACKEND=local-json
REPORT_STORAGE_LOCAL_PATH=.data/portal/research-briefing-storage.json
PORTAL_ACCOUNT_STORAGE_BACKEND=local-json
PORTAL_ACCOUNT_STORAGE_PATH=.data/portal/portal-accounts.json
PORTAL_ACCOUNT_GOOGLE_DRIVE_BACKUP=false
PORTAL_ACCOUNT_GOOGLE_DRIVE_BACKUP_FILENAME=portal-accounts.synology-backup.json
PORTAL_ACCOUNT_GOOGLE_DRIVE_BACKUP_FILE_ID=

OPENAI_API_KEY=
OPENAI_MODEL=gpt-5-nano
EOF
      log "Created minimal $PORTAL_RUNTIME_DIR/.env."
    fi
  fi

  chmod 600 "$PORTAL_RUNTIME_DIR/.env" 2>/dev/null || true
}

read_env_value() {
  file="$1"
  key="$2"
  [ -f "$file" ] || return 0
  sed -n \
    -e "s/^${key}=//p" \
    -e "s/^export[[:space:]]\\{1,\\}${key}=//p" \
    "$file" | tail -n 1 | sed "s/\r$//"
}

write_env_value() {
  file="$1"
  key="$2"
  value="$3"
  tmp="${file}.tmp.$$"

  mkdir -p "$(dirname "$file")"
  [ -f "$file" ] || : > "$file"

  awk -v key="$key" -v value="$value" '
    BEGIN { found = 0 }
    {
      sub(/\r$/, "", $0)
      if ($0 ~ "^" key "=" || $0 ~ "^export[[:space:]]+" key "=") {
        print key "=" value
        found = 1
      } else {
        print
      }
    }
    END {
      if (!found) {
        print key "=" value
      }
    }
  ' "$file" > "$tmp"

  mv "$tmp" "$file"
  chmod 600 "$file" 2>/dev/null || true
}

ensure_env_value() {
  file="$1"
  key="$2"
  value="$3"
  current=$(read_env_value "$file" "$key")
  if [ -n "$current" ]; then
    return
  fi
  write_env_value "$file" "$key" "$value"
}

append_csv_value() {
  file="$1"
  key="$2"
  value="$3"
  current=$(read_env_value "$file" "$key")

  if printf "%s" ",$current," | grep -q ",$value,"; then
    return
  fi

  if [ -n "$current" ]; then
    write_env_value "$file" "$key" "$current,$value"
  else
    write_env_value "$file" "$key" "$value"
  fi
}

remove_csv_value() {
  file="$1"
  key="$2"
  value="$3"
  current=$(read_env_value "$file" "$key")

  if [ -z "$current" ]; then
    return
  fi

  value_lc=$(printf "%s" "$value" | tr '[:upper:]' '[:lower:]')
  updated=$(printf "%s" "$current" | tr ',' '\n' | awk -v drop="$value_lc" '
    {
      clean = $0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", clean)
      lower = tolower(clean)
      if (clean != "" && lower != drop) {
        if (out != "") {
          out = out "," clean
        } else {
          out = clean
        }
      }
    }
    END { print out }
  ')

  if [ "$updated" != "$current" ]; then
    write_env_value "$file" "$key" "$updated"
  fi
}

auth_users_has_user() {
  users="$1"
  username="$2"
  printf "%s" "$users" | tr ',' '\n' | awk -v user="$username" '
    {
      entry_user = $0
      sub(/:.*/, "", entry_user)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", entry_user)
      if (entry_user == user) {
        found = 1
      }
    }
    END { exit found ? 0 : 1 }
  '
}

upsert_auth_user() {
  file="$1"
  username="$2"
  password="$3"
  current=$(read_env_value "$file" "APP_BASIC_AUTH_USERS")
  entry="${username}:${password}"

  if [ -n "$current" ] && auth_users_has_user "$current" "$username"; then
    next=$(printf "%s" "$current" | tr ',' '\n' | awk -v user="$username" -v replacement="$entry" '
      BEGIN { first = 1 }
      {
        raw = $0
        split(raw, parts, ":")
        entry_user = parts[1]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", entry_user)
        if (entry_user == user) {
          raw = replacement
        }
        if (raw != "") {
          if (!first) {
            printf ","
          }
          printf "%s", raw
          first = 0
        }
      }
    ')
    write_env_value "$file" "APP_BASIC_AUTH_USERS" "$next"
  elif [ -n "$current" ]; then
    write_env_value "$file" "APP_BASIC_AUTH_USERS" "$current,$entry"
  else
    write_env_value "$file" "APP_BASIC_AUTH_USERS" "$entry"
  fi
}

random_hex() {
  bytes="$1"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$bytes"
    return
  fi

  if [ -r /dev/urandom ] && command -v od >/dev/null 2>&1; then
    od -An -N "$bytes" -tx1 /dev/urandom | tr -d ' \n'
    printf "\n"
    return
  fi

  fail "No strong random generator found. Install openssl or provide IDENTITY_PASSWORD and PORTAL_AUTH_CHECK_SECRET."
}

generate_secret() {
  random_hex 32
}

sha256_hex() {
  value="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    printf "%s" "$value" | sha256sum | awk '{print $1}'
    return
  fi

  if command -v openssl >/dev/null 2>&1; then
    printf "%s" "$value" | openssl dgst -sha256 -hex | awk '{print $NF}'
    return
  fi

  fail "No SHA-256 tool found. Install coreutils sha256sum or openssl."
}

env_file_candidates() {
  for file in \
    "$PORTAL_RUNTIME_DIR/.env" \
    "$BASE_DIR/meta/.env" \
    "$BASE_DIR/search/.env" \
    "$BASE_DIR/omni/.env" \
    "$BASE_DIR/protocol/.env" \
    "$BASE_DIR/agi/.env" \
    "$BASE_DIR/AGI/.env" \
    "$BASE_DIR/finance/.env" \
    "$BASE_DIR/finance-wiregene/.env" \
    "$BASE_DIR/wiregene-finance/.env" \
    "$BASE_DIR/music/.env" \
    "$BASE_DIR/music-wiregene/.env" \
    "$BASE_DIR/music-wiregene/.env.production" \
    "$BASE_DIR/research-briefing/.env" \
    "$BASE_DIR/research-briefing-platform/.env" \
    "$BASE_DIR/research-briefing-platform/.env.local" \
    "$BASE_DIR/research-briefing-platform/.env.production" \
    "$BASE_DIR/arim-app/.env" \
    "$BASE_DIR/arim/.env" \
    "$BASE_DIR/dmfoot/.env" \
    "$BASE_DIR/diabetic-foot/.env" \
    "$BASE_DIR/Diabetic-foot_Screening-Wiregene-demo/.env" \
    "$BASE_DIR/sci-bbb/.env" \
    "$BASE_DIR/sci-experiment/.env" \
    "$BASE_DIR/hyunlab-wiregene-platform/.env" \
    "$BASE_DIR/wiregene-meta-analysis/.env" \
    "$BASE_DIR/wiregene-meta-analysis/.env.local" \
    "$BASE_DIR/wiregene-omni/.env" \
    "$BASE_DIR/wiregene-protocol/.env" \
    "$BASE_DIR/wiregene-homepage/.env" \
    "$BASE_DIR/wiregene-portal/.env" \
    "$BASE_DIR/wiregene-portal/.env.local"; do
    [ -f "$file" ] && printf "%s\n" "$file"
  done

  if [ -n "${TARGET_ENV_FILES:-}" ]; then
    printf "%s\n" "$TARGET_ENV_FILES" | tr ';' '\n'
  fi
}

unique_env_files() {
  env_file_candidates | awk 'NF && !seen[$0]++'
}

find_password_for_user_in_file() {
  file="$1"
  username="$2"
  auth_user=$(read_env_value "$file" "APP_BASIC_AUTH_USER")
  auth_password=$(read_env_value "$file" "APP_BASIC_AUTH_PASSWORD")
  if [ "$auth_user" = "$username" ] && [ -n "$auth_password" ]; then
    printf "%s\n" "$auth_password"
    return
  fi

  users=$(read_env_value "$file" "APP_BASIC_AUTH_USERS")
  printf "%s" "$users" | tr ',' '\n' | awk -v user="$username" '
    {
      raw = $0
      entry_user = raw
      sub(/:.*/, "", entry_user)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", entry_user)
      if (entry_user == user) {
        sub(/^[^:]*:/, "", raw)
        if (raw != "") {
          print raw
          exit
        }
      }
    }
  '
}

choose_identity_password() {
  if [ -n "${IDENTITY_PASSWORD:-}" ]; then
    printf "%s\n" "$IDENTITY_PASSWORD"
    return
  fi

  for file in $(unique_env_files); do
    password=$(find_password_for_user_in_file "$file" "$IDENTITY_USERNAME")
    if [ -n "$password" ]; then
      printf "%s\n" "$password"
      return
    fi
  done

  fail "No fixed password found for $IDENTITY_USERNAME. Re-run with IDENTITY_PASSWORD set, or configure $IDENTITY_USERNAME in an existing .env first. The password is not stored in Git or logs."
}

choose_shared_secret() {
  if [ -n "${PORTAL_AUTH_CHECK_SECRET:-}" ]; then
    printf "%s\n" "$PORTAL_AUTH_CHECK_SECRET"
    return
  fi

  if [ -n "${WIREGENE_AUTH_CHECK_SECRET:-}" ]; then
    printf "%s\n" "$WIREGENE_AUTH_CHECK_SECRET"
    return
  fi

  for file in $(unique_env_files); do
    secret=$(read_env_value "$file" "PORTAL_AUTH_CHECK_SECRET")
    [ -n "$secret" ] || secret=$(read_env_value "$file" "WIREGENE_AUTH_CHECK_SECRET")
    if [ -n "$secret" ]; then
      printf "%s\n" "$secret"
      return
    fi
  done
  generate_secret
}

patch_compose_file() {
  file="$1"
  [ -f "$file" ] || return 0

  needs_patch="false"
  if grep -q '^name: wiregene-portal$' "$file" 2>/dev/null; then
    needs_patch="true"
  fi
  if ! grep -q '^version:' "$file" 2>/dev/null; then
    needs_patch="true"
  fi
  [ "$needs_patch" = "true" ] || return 0

  cp -p "$file" "$file.bak.$(date '+%Y%m%d%H%M%S')" 2>/dev/null || true
  sed -i '/^name: wiregene-portal$/d' "$file"
  if ! grep -q '^version:' "$file"; then
    tmp="$file.tmp.$$"
    {
      echo 'version: "3.3"'
      cat "$file"
    } > "$tmp"
    mv "$tmp" "$file"
  fi
  log "Patched compose compatibility: $file"
}

configure_env_file() {
  file="$1"
  identity_password="$2"
  shared_secret="$3"

  cp -p "$file" "$file.bak.$(date '+%Y%m%d%H%M%S')" 2>/dev/null || true

  upsert_auth_user "$file" "$IDENTITY_USERNAME" "$identity_password"
  ensure_env_value "$file" "APP_BASIC_AUTH_SITE_ACCESS" "${LEGACY_SEARCH_USERNAME}=search"
  remove_csv_value "$file" "WIREGENE_ADMIN_EMAILS" "$LEGACY_SEARCH_USERNAME"
  remove_csv_value "$file" "APP_ADMIN_USERS" "$LEGACY_SEARCH_USERNAME"
  remove_csv_value "$file" "APP_ADMIN_USER" "$LEGACY_SEARCH_USERNAME"
  append_csv_value "$file" "WIREGENE_ADMIN_EMAILS" "$IDENTITY_USERNAME"
  write_env_value "$file" "PORTAL_AUTH_CHECK_SECRET" "$shared_secret"
  write_env_value "$file" "WIREGENE_AUTH_CHECK_SECRET" "$shared_secret"
  write_env_value "$file" "PORTAL_AUTH_CHECK_URL" "$PORTAL_AUTH_CHECK_URL"

  case "$file" in
    "$PORTAL_RUNTIME_DIR/.env")
      write_env_value "$file" "APP_SOURCE_DIR" "$PORTAL_SOURCE_DIR"
      write_env_value "$file" "HOST_PORT" "3002"
      write_env_value "$file" "CONTAINER_NAME" "wiregene-portal"
      write_env_value "$file" "APP_BASE_URL" "https://portal.wiregene.com"
      write_env_value "$file" "PUBLIC_PORTAL_HOST" "portal.wiregene.com"
      write_env_value "$file" "PUBLIC_PORTAL_ROUTE_POLICY" "synology"
      write_env_value "$file" "WIREGENE_APP_MODE" "portal"
      write_env_value "$file" "REPORT_STORAGE_BACKEND" "local-json"
      write_env_value "$file" "REPORT_STORAGE_LOCAL_PATH" ".data/portal/research-briefing-storage.json"
      write_env_value "$file" "PORTAL_ACCOUNT_STORAGE_BACKEND" "local-json"
      write_env_value "$file" "PORTAL_ACCOUNT_STORAGE_PATH" ".data/portal/portal-accounts.json"
      ensure_env_value "$file" "PORTAL_ACCOUNT_GOOGLE_DRIVE_BACKUP" "false"
      ensure_env_value "$file" "PORTAL_ACCOUNT_GOOGLE_DRIVE_BACKUP_FILENAME" "portal-accounts.synology-backup.json"
      ;;
  esac

  if grep -q '^ARIM_' "$file" 2>/dev/null; then
    add_arim_professor_account "$file" "$IDENTITY_USERNAME" "$identity_password"
  fi

  case "$file" in
    *music-wiregene* | *"/music/"* | *"/music."*)
      write_env_value "$file" "MUSIC_AUTH_USER" "$IDENTITY_USERNAME"
      write_env_value "$file" "MUSIC_AUTH_PASSWORD_SHA256" "$(sha256_hex "$identity_password")"
      if [ -z "$(read_env_value "$file" "MUSIC_AUTH_SECRET")" ]; then
        write_env_value "$file" "MUSIC_AUTH_SECRET" "$(generate_secret)"
      fi
      log "Configured Music auth settings in $file"
      ;;
  esac

  log "Configured identity/auth settings in $file"
}

add_arim_professor_account() {
  file="$1"
  username="$2"
  password="$3"
  current=$(read_env_value "$file" "ARIM_PROFESSOR_ACCOUNTS")

  entry="${username}:${password}"
  if [ -n "$current" ] && auth_users_has_user "$current" "$username"; then
    next=$(printf "%s" "$current" | tr ',' '\n' | awk -v user="$username" -v replacement="$entry" '
      BEGIN { first = 1 }
      {
        raw = $0
        split(raw, parts, ":")
        entry_user = parts[1]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", entry_user)
        if (entry_user == user) {
          raw = replacement
        }
        if (raw != "") {
          if (!first) {
            printf ","
          }
          printf "%s", raw
          first = 0
        }
      }
    ')
    write_env_value "$file" "ARIM_PROFESSOR_ACCOUNTS" "$next"
  elif [ -n "$current" ]; then
    write_env_value "$file" "ARIM_PROFESSOR_ACCOUNTS" "$current,$entry"
  else
    write_env_value "$file" "ARIM_PROFESSOR_ACCOUNTS" "$entry"
  fi
  log "Added $username to ARIM_PROFESSOR_ACCOUNTS in $file"
}

restart_known_services() {
  [ "$AUTO_START" = "true" ] || return 0

  if [ -f "$PORTAL_SOURCE_DIR/scripts/synology-update-portal.sh" ]; then
    /bin/sh "$PORTAL_SOURCE_DIR/scripts/synology-update-portal.sh"
  elif [ -f "$PORTAL_SOURCE_DIR/scripts/synology-start-portal.sh" ]; then
    /bin/sh "$PORTAL_SOURCE_DIR/scripts/synology-start-portal.sh"
  fi

  for runtime in \
    "$BASE_DIR/meta" \
    "$BASE_DIR/search" \
    "$BASE_DIR/research-briefing" \
    "$BASE_DIR/agi" \
    "$BASE_DIR/finance" \
    "$BASE_DIR/finance-wiregene" \
    "$BASE_DIR/music" \
    "$BASE_DIR/music-wiregene" \
    "$BASE_DIR/dmfoot" \
    "$BASE_DIR/diabetic-foot"; do
    if [ -f "$runtime/docker-compose.yml" ] && [ -f "$runtime/.env" ]; then
      log "Restarting compose runtime at $runtime."
      compose_up "$runtime/docker-compose.yml" "$runtime/.env" || log "WARNING: compose restart failed for $runtime."
    fi
  done
}

main() {
  mkdir -p "$LOG_DIR"
  rotate_log
  acquire_lock
  log "Wiregene identity auto-configuration started."
  ensure_repo
  ensure_portal_env

  patch_compose_file "$PORTAL_SOURCE_DIR/synology/docker/portal/docker-compose.yml"
  patch_compose_file "$PORTAL_RUNTIME_DIR/docker-compose.yml"

  identity_password=$(choose_identity_password)
  shared_secret=$(choose_shared_secret)

  for file in $(unique_env_files); do
    configure_env_file "$file" "$identity_password" "$shared_secret"
  done

  restart_known_services

  log "Wiregene identity auto-configuration finished."
  log "Configured username: $IDENTITY_USERNAME"
}

main "$@"
