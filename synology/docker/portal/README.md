# Synology Portal Service

This package runs `portal.wiregene.com` as a finite Synology Docker deployment.
The DSM scheduler must finish; it must not run web servers, `npm install`,
`npm run build`, `docker compose build`, `docker logs -f`, or `tail -f`.

## Runtime Layout

```text
/volume1/docker/wiregene-portal  Git checkout
/volume1/docker/portal           Runtime env, compose, data, logs, locks
/volume1/docker/portal/data      Persistent Portal local-json data
/volume1/docker/portal/logs      Bounded scheduler logs
```

Only these values should vary by Wiregene site:

```text
APP_DIR or source checkout path
RUNTIME_DIR
PORTAL_IMAGE
HOST_PORT
CONTAINER_NAME
PORTAL_LOCAL_HEALTH_URL
Required environment variables
```

## DSM Task Scheduler

Use this single command for manual or scheduled Portal deployment:

```sh
/bin/sh -lc 'set -eu; export PATH="/usr/local/bin:/opt/bin:/usr/bin:/bin:/usr/syno/bin:/var/packages/ContainerManager/target/usr/bin:/volume1/@appstore/ContainerManager/usr/bin:/var/packages/Docker/target/usr/bin:/volume1/@appstore/Docker/usr/bin:/var/packages/Git/target/bin:/volume1/@appstore/Git/bin:$PATH"; APP_DIR="/volume1/docker/wiregene-portal"; REPO_URL="https://github.com/rhhyun/wiregene-portal.git"; if [ ! -d "$APP_DIR/.git" ]; then if [ -e "$APP_DIR" ]; then echo "ERROR: $APP_DIR exists but is not a Git checkout."; exit 1; fi; git clone "$REPO_URL" "$APP_DIR"; fi; git -C "$APP_DIR" pull --ff-only origin main; /bin/sh "$APP_DIR/scripts/synology-update-portal.sh"'
```

The script:

- acquires `/volume1/docker/portal/.deploy.lock`;
- removes the lock on success, failure, or signal by trap;
- bounds Git, pull, compose, storage probe, and health checks with timeouts;
- runs `docker compose pull portal`;
- probes `/app/.data/portal` with create, rename, and delete operations;
- runs `docker compose up -d --remove-orphans`;
- never runs NAS `npm install`, NAS `npm run build`, compose build, prune, or volume deletion;
- checks container state, Docker healthcheck, `/api/health`, root HTTP `200/401`,
  rendered version when Basic Auth is available, and public route headers.

On first run, fill `/volume1/docker/portal/.env`, then run the same command
again. The default service listens on host port `3002`.

## Image Build

App images are built by GitHub Actions and pushed to:

```text
ghcr.io/rhhyun/wiregene-portal:latest
```

The NAS deploy path only pulls the prebuilt image. If GHCR is private, log in
once on the NAS with a GitHub token that has package read permission.

## Automatic Identity Setup

Use this when `rhhyun` must be added without manually editing every `.env`:

```sh
/bin/sh -lc 'set -eu; cd /volume1/docker/wiregene-portal; git pull --ff-only origin main; IDENTITY_PASSWORD="<provided master password>" /bin/sh /volume1/docker/wiregene-portal/scripts/synology-auto-wiregene-identity.sh'
```

The Master password is read from `IDENTITY_PASSWORD` or an existing `rhhyun`
entry. It is not generated automatically and is not printed to logs.

## Route Policy

Production must use fail-closed Synology routing:

```text
PUBLIC_PORTAL_ROUTE_POLICY=synology
```

The only temporary break-glass public Vercel route policy is:

```text
PUBLIC_PORTAL_ROUTE_POLICY=vercel-emergency
```

Emergency Vercel mode leaves Portal member management read-only. The legacy
value `warn` is treated as `synology`, and `SKIP_PUBLIC_PORTAL_ROUTE_CHECK=1`
is rejected.

## Status

```sh
/bin/sh /volume1/docker/wiregene-portal/scripts/synology-portal-status.sh
```

## Rollback

Replace `<previous-good-commit>` with a known good Git commit:

```sh
/bin/sh -lc 'set -eu; APP_DIR="/volume1/docker/wiregene-portal"; git -C "$APP_DIR" fetch origin; git -C "$APP_DIR" checkout <previous-good-commit>; /bin/sh "$APP_DIR/scripts/synology-update-portal.sh"'
```

If the image for the previous commit is needed directly:

```sh
PORTAL_IMAGE=ghcr.io/rhhyun/wiregene-portal:<previous-good-commit-sha> /bin/sh /volume1/docker/wiregene-portal/scripts/synology-update-portal.sh
```

## Account Backup

Portal account storage source of truth is Synology local JSON:

```text
PORTAL_ACCOUNT_STORAGE_BACKEND=local-json
PORTAL_ACCOUNT_STORAGE_PATH=.data/portal/portal-accounts.json
```

Google Drive is backup-only unless an emergency mode is explicitly enabled:

```sh
/bin/sh /volume1/docker/wiregene-portal/scripts/synology-backup-portal-accounts-google-drive.sh
```

## Public Route

If public traffic should reach Synology:

- DSM reverse proxy source: `HTTPS portal.wiregene.com:443`
- DSM reverse proxy destination: `HTTP 127.0.0.1:3002`
- Cloudflare DNS: `portal.wiregene.com` points to the Synology public endpoint
- Vercel: remove the `portal.wiregene.com` alias/domain binding only after the
  Synology route works
