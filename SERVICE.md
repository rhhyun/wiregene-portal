# Wiregene Portal

Standalone repository exported from `research-briefing-platform`.

## Service Boundary

- Host: https://portal.wiregene.com
- App mode: portal
- Synology source directory: /volume1/docker/wiregene-portal
- Runtime directory: /volume1/docker/portal

The source is intentionally copied rather than shared with `search.wiregene.com`
so deployments, Vercel aliases, Synology containers, and environment variables
cannot overwrite each other.

## First Commit

```powershell
git init
git add .
git commit -m "Initialize Wiregene Portal standalone app"
git branch -M main
git remote add origin https://github.com/rhhyun/empty1.git
git push -u origin main
```

Set `WIREGENE_APP_MODE=portal` in Vercel and Synology.
