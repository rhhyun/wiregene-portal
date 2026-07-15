# Synology Portal Service

This package runs `portal.wiregene.com` as a separate Synology Docker service.

## Install

```sh
/bin/sh /volume1/docker/wiregene-portal/scripts/synology-update-portal.sh
```

On the first run, fill `/volume1/docker/portal/.env`, then run the same command
again.

The default service listens on host port `3002`.

## Automatic Identity Setup

Use this when `rhhyun` must be added without manually editing every `.env`:

```sh
cd /volume1/docker/wiregene-portal && git pull --ff-only origin main && IDENTITY_PASSWORD='<provided master password>' /bin/sh /volume1/docker/wiregene-portal/scripts/synology-auto-wiregene-identity.sh
```

The script keeps existing `wiregene` credentials scoped to `search`, upserts
`rhhyun` in `APP_BASIC_AUTH_USERS`, marks `rhhyun` as an admin, shares
`PORTAL_AUTH_CHECK_SECRET` / `WIREGENE_AUTH_CHECK_SECRET` with known subsite
`.env` files, configures Music's `MUSIC_AUTH_USER` and
`MUSIC_AUTH_PASSWORD_SHA256`, and restarts the Portal plus known compose
runtimes when `AUTO_START=true`.

The Master password is read from `IDENTITY_PASSWORD` or an existing `rhhyun`
entry. It is not generated automatically and is not printed to logs.

The log is:

```text
/volume1/docker/portal/logs/identity-auto-config.log
```

## DSM Task Scheduler

Use this single command for manual or scheduled updates:

```sh
cd /volume1/docker/wiregene-portal && git pull --ff-only origin main && /bin/sh /volume1/docker/wiregene-portal/scripts/synology-update-portal.sh
```

The update script pulls the latest source, builds before restarting the service,
recreates the container only after a successful build, checks local HTTP
readiness, verifies the rendered `Ver x.y` label when Basic Auth credentials are
available, checks whether the public `portal.wiregene.com` route is still served
by Vercel, and writes a timestamped log under `/volume1/docker/portal/logs`.

The DSM scheduler fails if the public route reports Vercel headers or cannot be
verified. Production must use:

```text
PUBLIC_PORTAL_ROUTE_POLICY=synology
```

The only temporary break-glass route policy is:

```text
PUBLIC_PORTAL_ROUTE_POLICY=vercel-emergency
```

This emergency mode leaves Portal member management read-only. The legacy
value `warn` is treated as `synology` and no longer bypasses the route check.
`SKIP_PUBLIC_PORTAL_ROUTE_CHECK=1` is rejected. Before the container restarts,
the startup script verifies the mounted account directory using create, rename,
and delete operations.

The required public route is:

- DSM reverse proxy source: `HTTPS portal.wiregene.com:443`
- DSM reverse proxy destination: `HTTP 127.0.0.1:3002`
- Cloudflare DNS: `portal.wiregene.com` must point to the Synology public
  endpoint, not Vercel `76.76.21.21`
- Vercel: remove the `portal.wiregene.com` alias/domain binding only after the
  Synology route works

## Required Source

The shared GitHub source should exist at:

```text
/volume1/docker/wiregene-portal
```

Change `APP_SOURCE_DIR` in `.env` if the checkout lives elsewhere.
