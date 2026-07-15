#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
UPDATE_SCRIPT="$SCRIPT_DIR/synology-update-portal.sh"
TMP_DIR="${TMPDIR:-/tmp}/wiregene-portal-route-policy-$$"
RUNTIME_DIR="$TMP_DIR/runtime"
BIN_DIR="$TMP_DIR/bin"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$RUNTIME_DIR/logs" "$BIN_DIR"

cat > "$BIN_DIR/curl" <<'EOF'
#!/bin/sh
cat <<'HEADERS'
HTTP/2 401
server: Vercel
x-vercel-id: test-route-policy
HEADERS
EOF
chmod +x "$BIN_DIR/curl"

write_policy() {
  cat > "$RUNTIME_DIR/.env" <<EOF
PUBLIC_PORTAL_HOST=portal.wiregene.com
PUBLIC_PORTAL_ROUTE_POLICY=$1
EOF
}

expect_failure() {
  policy="$1"
  write_policy "$policy"
  if PATH="$BIN_DIR:/usr/bin:/bin" \
    PORTAL_ROUTE_CHECK_ONLY=1 \
    PORTAL_RUNTIME_DIR="$RUNTIME_DIR" \
    PORTAL_LOG_DIR="$RUNTIME_DIR/logs" \
    /bin/sh "$UPDATE_SCRIPT" >/dev/null 2>&1; then
    echo "ERROR: route policy unexpectedly passed: $policy" >&2
    exit 1
  fi
}

expect_success() {
  policy="$1"
  write_policy "$policy"
  PATH="$BIN_DIR:/usr/bin:/bin" \
    PORTAL_ROUTE_CHECK_ONLY=1 \
    PORTAL_RUNTIME_DIR="$RUNTIME_DIR" \
    PORTAL_LOG_DIR="$RUNTIME_DIR/logs" \
    /bin/sh "$UPDATE_SCRIPT" >/dev/null 2>&1
}

expect_failure synology
expect_failure warn
expect_failure invalid-policy
expect_success vercel-emergency

write_policy vercel-emergency
echo "SKIP_PUBLIC_PORTAL_ROUTE_CHECK=1" >> "$RUNTIME_DIR/.env"
if PATH="$BIN_DIR:/usr/bin:/bin" \
  PORTAL_ROUTE_CHECK_ONLY=1 \
  PORTAL_RUNTIME_DIR="$RUNTIME_DIR" \
  PORTAL_LOG_DIR="$RUNTIME_DIR/logs" \
  /bin/sh "$UPDATE_SCRIPT" >/dev/null 2>&1; then
  echo "ERROR: SKIP_PUBLIC_PORTAL_ROUTE_CHECK bypass unexpectedly passed" >&2
  exit 1
fi

echo "synology_route_policy_tests=passed"
