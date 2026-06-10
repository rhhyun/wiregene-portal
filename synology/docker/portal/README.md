# Synology Portal Service

This package runs `portal.wiregene.com` as a separate Synology Docker service.

## Install

```sh
/bin/sh /volume1/docker/wiregene-portal/scripts/synology-start-portal.sh
```

On the first run, fill `/volume1/docker/portal/.env`, then run the same command
again.

The default service listens on host port `3002`.

## Required Source

The shared GitHub source should exist at:

```text
/volume1/docker/wiregene-portal
```

Change `APP_SOURCE_DIR` in `.env` if the checkout lives elsewhere.
