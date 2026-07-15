const isEnabled = (value) => value?.trim().toLowerCase() === "true";

const isVercel = Boolean(process.env.VERCEL);
const appMode = process.env.WIREGENE_APP_MODE?.trim().toLowerCase();
const repoSlug = process.env.VERCEL_GIT_REPO_SLUG?.trim().toLowerCase();
const productionUrl = process.env.VERCEL_PROJECT_PRODUCTION_URL?.trim().toLowerCase();
const isPortalBuild =
  appMode === "portal" ||
  repoSlug === "wiregene-portal" ||
  productionUrl === "wiregene-portal.vercel.app";
const emergencyDeployAllowed = isEnabled(process.env.PORTAL_ALLOW_VERCEL_EMERGENCY_DEPLOY);

if (isVercel && isPortalBuild && !emergencyDeployAllowed) {
  console.error(
    [
      "[portal-runtime-policy] Refusing to build Wiregene Portal on Vercel.",
      "Production account writes require the Synology local-json runtime.",
      "Deploy through the Synology scheduler instead.",
      "For a time-boxed emergency Vercel deployment only, explicitly set",
      "PORTAL_ALLOW_VERCEL_EMERGENCY_DEPLOY=true and keep account management read-only.",
    ].join("\n"),
  );
  process.exit(1);
}

console.log(
  `[portal-runtime-policy] allowed runtime=${isVercel ? "vercel" : "non-vercel"} portal=${isPortalBuild}`,
);
