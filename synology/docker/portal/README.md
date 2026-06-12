# Synology Portal Service

This package runs `portal.wiregene.com` as a separate Synology Docker service.

## Install

```sh
/bin/sh /volume1/docker/wiregene-portal/scripts/synology-update-portal.sh
```

On the first run, fill `/volume1/docker/portal/.env`, then run the same command
again.

The default service listens on host port `3002`.

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

If the public route check reports Vercel headers, the local Synology container
was updated correctly but browsers are still reaching Vercel. This is expected
when Portal is intentionally served from Vercel with Google Drive account
storage. In that mode, fix the Portal Vercel Google Drive OAuth values instead
of changing Synology.

To make the DSM scheduler fail whenever the public host is still Vercel, set:

```text
PUBLIC_PORTAL_ROUTE_POLICY=synology
```

To keep Vercel as the public host while Synology is only a local/runtime copy,
leave the default:

```text
PUBLIC_PORTAL_ROUTE_POLICY=warn
```

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
