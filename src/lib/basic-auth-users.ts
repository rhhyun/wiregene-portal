import crypto from "crypto";

export type BasicAuthCredential = {
  username: string;
  password: string;
  source: "APP_BASIC_AUTH_USER" | "APP_BASIC_AUTH_USERS";
};

type BasicAuthEnv = Record<string, string | undefined>;

export type ProvidedBasicAuthCredential = Pick<BasicAuthCredential, "username" | "password">;
export type BasicAuthAccountSummary = {
  username: string;
  source: BasicAuthCredential["source"];
  passwordConfigured: boolean;
  role: "admin" | "user";
  sites: string[];
};

export const WIREGENE_ADMIN_SITE_IDS = [
  "portal",
  "homepage-admin",
  "omni",
  "protocol",
  "search",
  "meta",
  "hyunlab",
  "sci-experiment",
  "behavior",
  "human",
];

const WIREGENE_SITE_ID_SET = new Set(WIREGENE_ADMIN_SITE_IDS);
const WIREGENE_SITE_ID_ALIASES: Record<string, string> = {
  arim: "human",
  homepage: "homepage-admin",
  "www-admin": "homepage-admin",
  "www.wiregene.com/admin": "homepage-admin",
  "sci-bbb": "behavior",
};
const RESERVED_NON_ADMIN_USERNAMES = new Set(["wiregene"]);

export function getBasicAuthCredentialsFromEnv(env: BasicAuthEnv = process.env) {
  const credentials: BasicAuthCredential[] = [];
  const username = normalizeAuthEnvValue(env.APP_BASIC_AUTH_USER);
  const password = normalizeAuthEnvValue(env.APP_BASIC_AUTH_PASSWORD);

  if (username && password) {
    credentials.push({
      username,
      password,
      source: "APP_BASIC_AUTH_USER",
    });
  }

  credentials.push(...parseBasicAuthUsers(normalizeAuthEnvValue(env.APP_BASIC_AUTH_USERS)));
  return credentials;
}

export function getBasicAuthAccountSummaries(env: BasicAuthEnv = process.env) {
  const adminUsernames = getAdminUsernamesFromEnv(env);
  const siteAccess = getBasicAuthSiteAccessFromEnv(env);

  return getBasicAuthCredentialsFromEnv(env).map((credential): BasicAuthAccountSummary => {
    const normalizedUsername = normalizeAuthUsername(credential.username);
    const isAdmin = adminUsernames.has(normalizedUsername);

    return {
      username: credential.username,
      source: credential.source,
      passwordConfigured: Boolean(credential.password),
      role: isAdmin ? "admin" : "user",
      sites: isAdmin
        ? WIREGENE_ADMIN_SITE_IDS
        : basicAuthSitesForUsername(normalizedUsername, siteAccess.get(normalizedUsername)),
    };
  });
}

export function findBasicAuthAccountForCredential(
  provided: ProvidedBasicAuthCredential,
  env: BasicAuthEnv = process.env,
): BasicAuthAccountSummary | null {
  const credential = getBasicAuthCredentialsFromEnv(env).find((candidate) =>
    basicAuthCredentialsMatch(candidate, provided),
  );
  if (!credential) return null;

  return (
    getBasicAuthAccountSummaries(env).find(
      (account) => account.username === credential.username && account.source === credential.source,
    ) ?? null
  );
}

export function basicAuthCredentialsMatch(
  expected: Pick<BasicAuthCredential, "username" | "password">,
  provided: ProvidedBasicAuthCredential,
) {
  return expected.username === provided.username && timingSafeStringEqual(expected.password, provided.password);
}

export function getAdminUsernamesFromEnv(env: BasicAuthEnv = process.env) {
  return new Set(
    parseAdminUsers(
      [
        normalizeAuthEnvValue(env.WIREGENE_ADMIN_EMAILS),
        normalizeAuthEnvValue(env.APP_ADMIN_USERS),
        normalizeAuthEnvValue(env.APP_ADMIN_USER),
      ].join(","),
    ).filter((username) => !RESERVED_NON_ADMIN_USERNAMES.has(username)),
  );
}

export function getBasicAuthSiteAccessFromEnv(env: BasicAuthEnv = process.env) {
  return parseBasicAuthSiteAccess(normalizeAuthEnvValue(env.APP_BASIC_AUTH_SITE_ACCESS));
}

export function isAdminUsername(username: string, env: BasicAuthEnv = process.env) {
  return getAdminUsernamesFromEnv(env).has(normalizeAuthUsername(username));
}

export function parseBasicAuthCredential(authorization: string): ProvidedBasicAuthCredential | null {
  const [scheme, encoded] = authorization.split(" ");

  if (scheme?.toLowerCase() !== "basic" || !encoded) return null;

  try {
    const decoded = atob(encoded);
    const separatorIndex = decoded.indexOf(":");

    if (separatorIndex < 0) return null;

    return {
      username: decoded.slice(0, separatorIndex),
      password: decoded.slice(separatorIndex + 1),
    };
  } catch {
    return null;
  }
}

export function normalizeAuthUsername(value: string) {
  return value.trim().toLowerCase();
}

export function normalizeAuthEnvValue(value: string | undefined) {
  if (!value) return "";

  const trimmed = value.trim();
  if (!trimmed || trimmed === '""' || trimmed === "''") return "";

  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1);
  }

  return trimmed;
}

function parseBasicAuthUsers(value: string | undefined): BasicAuthCredential[] {
  if (!value) return [];

  return value.split(",").flatMap((entry) => {
    const trimmedEntry = entry.trim();
    const separatorIndex = trimmedEntry.indexOf(":");

    if (separatorIndex <= 0) return [];

    const username = trimmedEntry.slice(0, separatorIndex).trim();
    const password = trimmedEntry.slice(separatorIndex + 1);

    if (!username || !password) return [];
    return [{ username, password, source: "APP_BASIC_AUTH_USERS" as const }];
  });
}

function parseAdminUsers(value: string | undefined): string[] {
  if (!value) return [];

  return value
    .split(",")
    .map((entry) => normalizeAuthUsername(entry))
    .filter(Boolean);
}

function basicAuthSitesForUsername(normalizedUsername: string, configuredSites?: string[]) {
  if (normalizedUsername === "wiregene") return ["search"];
  return configuredSites ?? ["portal"];
}

function parseBasicAuthSiteAccess(value: string | undefined) {
  const siteAccess = new Map<string, string[]>();
  if (!value) return siteAccess;

  for (const entry of value.split(",")) {
    const separatorIndex = entry.indexOf("=");
    if (separatorIndex <= 0) continue;

    const username = normalizeAuthUsername(entry.slice(0, separatorIndex));
    const sites = Array.from(
      new Set(
        entry
          .slice(separatorIndex + 1)
          .split(/[|;\s]+/)
          .map(normalizeSiteId)
          .filter((site) => WIREGENE_SITE_ID_SET.has(site)),
      ),
    );

    if (username && sites.length > 0) {
      siteAccess.set(username, sites);
    }
  }

  return siteAccess;
}

function normalizeSiteId(value: string) {
  const normalized = value.trim().toLowerCase();
  return WIREGENE_SITE_ID_ALIASES[normalized] ?? normalized;
}

function timingSafeStringEqual(expected: string, provided: string) {
  const expectedBytes = Buffer.from(expected);
  const providedBytes = Buffer.from(provided);

  if (expectedBytes.length !== providedBytes.length) {
    const paddedProvided = Buffer.alloc(expectedBytes.length);
    providedBytes.copy(paddedProvided, 0, 0, Math.min(providedBytes.length, paddedProvided.length));
    crypto.timingSafeEqual(expectedBytes, paddedProvided);
    return false;
  }

  return crypto.timingSafeEqual(expectedBytes, providedBytes);
}
