import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const policyScript = fileURLToPath(new URL("./verify-portal-runtime-policy.mjs", import.meta.url));

function runPolicy(overrides) {
  const env = { ...process.env };
  for (const key of [
    "VERCEL",
    "WIREGENE_APP_MODE",
    "VERCEL_GIT_REPO_SLUG",
    "VERCEL_PROJECT_PRODUCTION_URL",
    "PORTAL_ALLOW_VERCEL_EMERGENCY_DEPLOY",
  ]) {
    delete env[key];
  }
  Object.assign(env, overrides);
  return spawnSync(process.execPath, [policyScript], { env, encoding: "utf8" });
}

assert.equal(runPolicy({ WIREGENE_APP_MODE: "portal" }).status, 0, "Synology/local builds must pass");
assert.notEqual(
  runPolicy({ VERCEL: "1", WIREGENE_APP_MODE: "portal" }).status,
  0,
  "Portal Vercel builds must fail closed",
);
assert.notEqual(
  runPolicy({ VERCEL: "1", VERCEL_GIT_REPO_SLUG: "wiregene-portal" }).status,
  0,
  "The portal repository must be detected even if app mode is missing",
);
assert.equal(
  runPolicy({
    VERCEL: "1",
    WIREGENE_APP_MODE: "portal",
    PORTAL_ALLOW_VERCEL_EMERGENCY_DEPLOY: "true",
  }).status,
  0,
  "Explicit emergency Vercel builds must remain available",
);
assert.equal(
  runPolicy({ VERCEL: "1", WIREGENE_APP_MODE: "search" }).status,
  0,
  "Non-Portal Vercel builds must not be blocked",
);

console.log("portal_runtime_policy_tests=passed");
