# Wiregene Portal Synology Deployment

## Audit Result

Before this hardening, the documented DSM command was:

```sh
cd /volume1/docker/wiregene-portal && git pull --ff-only origin main && /bin/sh /volume1/docker/wiregene-portal/scripts/synology-update-portal.sh
```

The command called `scripts/synology-start-portal.sh`, which ran `npm ci` or
`npm install` and `npm run build` on the NAS before `docker compose up -d
--force-recreate`. The compose service used the generic `node:24-bookworm-slim`
image plus a source bind mount and had no Docker `healthcheck` or Docker log
rotation. `scripts/synology-web-start.sh` also kept legacy NAS build and
foreground-server paths.

No `docker compose up` without `-d`, `docker logs -f`, `tail -f`,
`docker compose build`, `docker system prune -a`, or `docker volume prune` was
found in the active Portal scheduler path. The major risks were unbounded NAS
build, missing lock/trap, missing timeout, missing Docker healthcheck, and
append-only logs.

## After

The Portal deployment now follows this finite rule:

```text
GitHub Actions builds image -> GHCR stores image -> NAS pulls image -> docker compose up -d --remove-orphans
```

The NAS deployment scripts do not build application code. Existing running
containers and persistent data are not deleted on failure.

## Common Wiregene Deploy Contract

Shared behavior for every Wiregene subsite should live in
`scripts/synology-deploy-common.sh`:

- deterministic DSM `PATH`;
- docker/docker-compose discovery;
- lock directory with trap cleanup;
- bounded command execution with watchdog timeout;
- bounded scheduler log rotation;
- compose runtime helper;
- Docker health and HTTP health verification.

Only these values should vary per site:

```text
APP_DIR
RUNTIME_DIR
IMAGE
HOST_PORT
CONTAINER_NAME
HEALTH_URL
Required environment variables
```

Do not put these in site deployment scripts:

```text
npm install
npm ci
npm run build
docker compose build
docker compose up without -d
docker logs -f
tail -f
docker system prune -a
docker volume prune
unbounded docker rm -f
```

## Separated Non-Deploy Workers

These scripts are not Portal web deployment entrypoints and must not be used as
the Portal DSM deployment task:

```text
scripts/synology-briefing-generate.sh
scripts/synology-run-research-briefing.sh
scripts/synology-merge-sci-experiment.sh
```

They are long-running research/briefing maintenance jobs. If they are needed,
schedule them separately with their own lock, timeout, and retention policy.
They are intentionally outside the Portal container deploy path.

## Changed Files

- `scripts/synology-deploy-common.sh`: reusable Synology deploy helpers.
- `scripts/synology-update-portal.sh`: finite full deploy entrypoint.
- `scripts/synology-start-portal.sh`: image pull plus `up -d --remove-orphans`.
- `scripts/synology-portal-status.sh`: post-deploy status and leftover-process check.
- `scripts/synology-backup-portal-accounts-google-drive.sh`: backup job lock and timeout.
- `scripts/synology-auto-wiregene-identity.sh`: lock, log rotation, hard fail on Git pull, `--remove-orphans`.
- `scripts/synology-web-start.sh`: legacy foreground/build helper disabled by default.
- `synology/docker/portal/docker-compose.yml`: GHCR app image, healthcheck, log rotation.
- `.github/workflows/docker-portal.yml`: builds and pushes GHCR image.
- `Dockerfile`, `.dockerignore`: external CI image build.
- `src/app/api/health/route.ts`: unauthenticated container health endpoint.
- `src/proxy.ts`: allows `/api/health`.
- `src/lib/version.ts`: `Ver 1.74`.

## Final DSM Task Scheduler Command

```sh
/bin/sh -lc 'set -eu; export PATH="/usr/local/bin:/opt/bin:/usr/bin:/bin:/usr/syno/bin:/var/packages/ContainerManager/target/usr/bin:/volume1/@appstore/ContainerManager/usr/bin:/var/packages/Docker/target/usr/bin:/volume1/@appstore/Docker/usr/bin:/var/packages/Git/target/bin:/volume1/@appstore/Git/bin:$PATH"; APP_DIR="/volume1/docker/wiregene-portal"; REPO_URL="https://github.com/rhhyun/wiregene-portal.git"; if [ ! -d "$APP_DIR/.git" ]; then if [ -e "$APP_DIR" ]; then echo "ERROR: $APP_DIR exists but is not a Git checkout."; exit 1; fi; git clone "$REPO_URL" "$APP_DIR"; fi; git -C "$APP_DIR" pull --ff-only origin main; /bin/sh "$APP_DIR/scripts/synology-update-portal.sh"'
```

## Verification Commands

```sh
/bin/sh /volume1/docker/wiregene-portal/scripts/synology-portal-status.sh
curl -fsS http://127.0.0.1:3002/api/health
docker inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' wiregene-portal
docker compose -f /volume1/docker/portal/docker-compose.yml --env-file /volume1/docker/portal/.env ps
ps | grep -E 'synology-update-portal|synology-start-portal|docker logs -f|tail -f|npm run dev|next dev' | grep -v grep || true
```

## Rollback Commands

Rollback to a known good commit:

```sh
/bin/sh -lc 'set -eu; APP_DIR="/volume1/docker/wiregene-portal"; git -C "$APP_DIR" fetch origin; git -C "$APP_DIR" checkout <previous-good-commit>; /bin/sh "$APP_DIR/scripts/synology-update-portal.sh"'
```

Rollback to a specific image tag:

```sh
PORTAL_IMAGE=ghcr.io/rhhyun/wiregene-portal:<previous-good-commit-sha> /bin/sh /volume1/docker/wiregene-portal/scripts/synology-update-portal.sh
```

Do not run prune commands for rollback. Do not delete `/volume1/docker/portal/data`.
