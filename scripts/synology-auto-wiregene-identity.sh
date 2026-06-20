#!/bin/sh
set -eu

BASE_DIR="${BASE_DIR:-/volume1/docker}"
PORTAL_SOURCE_DIR="${PORTAL_SOURCE_DIR:-$BASE_DIR/wiregene-portal}"
PORTAL_RUNTIME_DIR="${PORTAL_RUNTIME_DIR:-$BASE_DIR/portal}"
PORTAL_REPO_URL="${PORTAL_REPO_URL:-https://github.com/rhhyun/wiregene-portal.git}"
IDENTITY_USERNAME="${IDENTITY_USERNAME:-rhhyun}"
REFERENCE_USERNAME="${REFERENCE_USERNAME:-wiregene}"
PORTAL_AUTH_CHECK_URL="${PORTAL_AUTH_CHECK_URL:-https://portal.wiregene.com/api/auth/check}"
PASSWORD_FILE="${PASSWORD_FILE:-$PORTAL_RUNTIME_DIR/${IDENTITY_USERNAME}-initial-password.txt}"
AUTO_START="${AUTO_START:-true}"

LOG_DIR="${PORTAL_RUNTIME_DIR}/logs"
LOG_FILE="${LOG_DIR}/identity-auto-config.log"

log() {
  mkdir -p "$LOG_DIR"
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
    docker compose -f "$compose_file" --env-file "$env_file" up -d
    return
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    if docker-compose -f "$compose_file" --env-file "$env_file" up -d; then
      return
    fi
    log "docker-compose rejected --env-file; retrying from $runtime_dir."
    (cd "$runtime_dir" && docker-compose -f docker-compose.yml up -d)
    return
  fi

  fail "Docker Compose was not found."
}

ensure_repo() {
  mkdir -p "$BASE_DIR"

  if [ -d "$PORTAL_SOURCE_DIR/.git" ]; then
    log "Updating portal source checkout at $PORTAL_SOURCE_DIR."
    git -C "$PORTAL_SOURCE_DIR" pull --ff-only origin main || log "WARNING: git pull failed; continuing with local checkout."
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
HOST_PORT=3002
CONTAINER_NAME=wiregene-portal

APP_BASE_URL=https://portal.wiregene.com
PUBLIC_PORTAL_HOST=portal.wiregene.com
PUBLIC_PORTAL_ROUTE_POLICY=warn
WIREGENE_APP_MODE=portal

APP_BASIC_AUTH_USER=
APP_BASIC_AUTH_PASSWORD=
APP_BASIC_AUTH_USERS=
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
  found="false"

  mkdir -p "$(dirname "$file")"
  [ -f "$file" ] || : > "$file"

  while IFS= read -r line || [ -n "$line" ]; do
    clean_line=$(printf "%s" "$line" | sed "s/\r$//")
    case "$clean_line" in
      "$key="* | "export $key="*)
        printf "%s=%s\n" "$key" "$value" >> "$tmp"
        found="true"
        ;;
      *)
        printf "%s\n" "$clean_line" >> "$tmp"
        ;;
    esac
  done < "$file"

  if [ "$found" != "true" ]; then
    printf "%s=%s\n" "$key" "$value" >> "$tmp"
  fi

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

auth_users_has_user() {
  users="$1"
  username="$2"
  printf "%s" "$users" | tr ',' '\n' | while IFS= read -r entry; do
    entry_username=$(printf "%s" "$entry" | sed 's/:.*$//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ "$entry_username" = "$username" ]; then
      printf "yes\n"
      exit 0
    fi
  done | grep -q '^yes$'
}

add_auth_user() {
  file="$1"
  username="$2"
  password="$3"
  current=$(read_env_value "$file" "APP_BASIC_AUTH_USERS")

  if auth_users_has_user "$current" "$username"; then
    return
  fi

  entry="${username}:${password}"
  if [ -n "$current" ]; then
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

generate_password() {
  printf "Wg-%s\n" "$(random_hex 12)"
}

env_file_candidates() {
  for file in \
    "$PORTAL_RUNTIME_DIR/.env" \
    "$BASE_DIR/meta/.env" \
    "$BASE_DIR/search/.env" \
    "$BASE_DIR/omni/.env" \
    "$BASE_DIR/protocol/.env" \
    "$BASE_DIR/research-briefing/.env" \
    "$BASE_DIR/research-briefing-platform/.env" \
    "$BASE_DIR/research-briefing-platform/.env.local" \
    "$BASE_DIR/research-briefing-platform/.env.production" \
    "$BASE_DIR/arim-app/.env" \
    "$BASE_DIR/arim/.env" \
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
  printf "%s" "$users" | tr ',' '\n' | while IFS= read -r entry; do
    entry_username=$(printf "%s" "$entry" | sed 's/:.*$//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    entry_password=$(printf "%s" "$entry" | sed 's/^[^:]*://')
    if [ "$entry_username" = "$username" ] && [ -n "$entry_password" ]; then
      printf "%s\n" "$entry_password"
      exit 0
    fi
  done | head -n 1
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

  for file in $(unique_env_files); do
    password=$(find_password_for_user_in_file "$file" "$REFERENCE_USERNAME")
    if [ -n "$password" ]; then
      log "Using existing $REFERENCE_USERNAME password for $IDENTITY_USERNAME without printing it."
      printf "%s\n" "$password"
      return
    fi
  done

  generated=$(generate_password)
  mkdir -p "$(dirname "$PASSWORD_FILE")"
  umask 077
  {
    printf "username=%s\n" "$IDENTITY_USERNAME"
    printf "password=%s\n" "$generated"
    printf "created_at=%s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
  } > "$PASSWORD_FILE"
  chmod 600 "$PASSWORD_FILE" 2>/dev/null || true
  log "Generated initial password for $IDENTITY_USERNAME and stored it at $PASSWORD_FILE."
  printf "%s\n" "$generated"
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
      echo 'version: "3.8"'
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

  add_auth_user "$file" "$IDENTITY_USERNAME" "$identity_password"
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
      write_env_value "$file" "PUBLIC_PORTAL_ROUTE_POLICY" "warn"
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

  log "Configured identity/auth settings in $file"
}

add_arim_professor_account() {
  file="$1"
  username="$2"
  password="$3"
  current=$(read_env_value "$file" "ARIM_PROFESSOR_ACCOUNTS")

  if auth_users_has_user "$current" "$username"; then
    return
  fi

  entry="${username}:${password}"
  if [ -n "$current" ]; then
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

  for runtime in "$BASE_DIR/meta" "$BASE_DIR/search" "$BASE_DIR/research-briefing"; do
    if [ -f "$runtime/docker-compose.yml" ] && [ -f "$runtime/.env" ]; then
      log "Restarting compose runtime at $runtime."
      compose_up "$runtime/docker-compose.yml" "$runtime/.env" || log "WARNING: compose restart failed for $runtime."
    fi
  done
}

main() {
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
  if [ -f "$PASSWORD_FILE" ]; then
    log "Initial generated password is stored at $PASSWORD_FILE"
  fi
}

main "$@"
