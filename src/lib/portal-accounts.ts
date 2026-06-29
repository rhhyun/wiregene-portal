import crypto from "crypto";
import { promisify } from "util";
import { createGrantJsonStorage } from "./grant-storage";

const scrypt = promisify(crypto.scrypt);
const manualPortalPasswordMinimumLength = 8;
const manualSitePasswordMinimumLength = 12;
const sharedSearchOnlyPortalUsernames = new Set(["wiregene"]);
const allowVercelGoogleDrivePrimary = process.env.PORTAL_ALLOW_VERCEL_GOOGLE_DRIVE_PRIMARY === "true";

export const portalSites = [
  {
    id: "portal",
    label: "Portal",
    shortLabel: "Portal",
    url: "https://portal.wiregene.com",
    identityOwner: "portal",
    accountManagementUrl: "https://portal.wiregene.com",
    accountManagementLabel: "Portal 계정 관리",
    accountPolicy: "Portal 접속 계정만 이곳에서 관리합니다.",
  },
  {
    id: "homepage-admin",
    label: "Wiregene Homepage Admin",
    shortLabel: "WWW Admin",
    url: "https://admin.wiregene.com",
    identityOwner: "subsite",
    accountManagementUrl: "https://admin.wiregene.com/admin",
    accountManagementLabel: "admin.wiregene.com 관리자 ID",
    accountPolicy: "홈페이지 관리자 ID/PW는 admin.wiregene.com에서 자체 관리합니다.",
  },
  {
    id: "search",
    label: "Research Search",
    shortLabel: "Search",
    url: "https://search.wiregene.com",
    identityOwner: "subsite",
    accountManagementUrl: "https://search.wiregene.com",
    accountManagementLabel: "Search 자체 계정",
    accountPolicy: "Search ID/PW는 Search 서비스에서 자체 관리하고 Portal은 연결만 담당합니다.",
  },
  {
    id: "omni",
    label: "Wiregene Omni",
    shortLabel: "Omni",
    url: "https://omni.wiregene.com",
    identityOwner: "subsite",
    accountManagementUrl: "https://omni.wiregene.com",
    accountManagementLabel: "Omni 자체 계정",
    accountPolicy: "Omni ID/PW는 Omni 서비스에서 자체 관리하고 Portal은 연결만 담당합니다.",
  },
  {
    id: "protocol",
    label: "Research Protocol",
    shortLabel: "Protocol",
    url: "https://protocol.wiregene.com",
    identityOwner: "subsite",
    accountManagementUrl: "https://protocol.wiregene.com",
    accountManagementLabel: "Protocol 자체 계정",
    accountPolicy: "Protocol ID/PW는 Protocol 서비스에서 자체 관리하고 Portal은 연결만 담당합니다.",
  },
  {
    id: "meta",
    label: "Meta-analysis",
    shortLabel: "Meta",
    url: "https://meta.wiregene.com",
    identityOwner: "subsite",
    accountManagementUrl: "https://meta.wiregene.com",
    accountManagementLabel: "Meta 자체 계정",
    accountPolicy: "Meta ID/PW는 Meta 서비스에서 자체 관리하고 Portal은 연결만 담당합니다.",
  },
  {
    id: "finance",
    label: "Finance Brain",
    shortLabel: "Finance",
    url: "https://finance.wiregene.com",
    identityOwner: "portal",
    accountManagementUrl: "https://portal.wiregene.com",
    accountManagementLabel: "Portal rhhyun account",
    accountPolicy: "Finance Brain uses the same rhhyun ID/PW as portal.wiregene.com.",
  },
  {
    id: "music",
    label: "Hyunlab AGI MusicScore",
    shortLabel: "Music",
    url: "https://music.wiregene.com",
    identityOwner: "subsite",
    accountManagementUrl: "https://music.wiregene.com/login",
    accountManagementLabel: "MusicScore 자체 계정",
    accountPolicy: "MusicScore ID/PW는 MusicScore 서비스에서 자체 관리하고 Portal은 연결만 담당합니다.",
  },
  {
    id: "hyunlab",
    label: "HyunLab Wiregene Platform",
    shortLabel: "HW ERP",
    url: "https://hyunlab.wiregene.com",
    identityOwner: "subsite",
    accountManagementUrl: "https://hyunlab.wiregene.com",
    accountManagementLabel: "HyunLab 자체 계정",
    accountPolicy: "HyunLab ERP ID/PW는 HyunLab 서비스에서 자체 관리하고 Portal은 연결만 담당합니다.",
  },
  {
    id: "sci-experiment",
    label: "SCI Experiment",
    shortLabel: "SCI EXP",
    url: "https://sci-experiment.wiregene.com",
    identityOwner: "subsite",
    accountManagementUrl: "https://sci-experiment.wiregene.com",
    accountManagementLabel: "SCI Experiment 자체 계정",
    accountPolicy: "SCI Experiment ID/PW는 해당 서비스에서 자체 관리하고 Portal은 연결만 담당합니다.",
  },
  {
    id: "behavior",
    label: "SCI BBB AI",
    shortLabel: "SCI BBB AI",
    url: "https://sci-bbb.wiregene.com",
    identityOwner: "subsite",
    accountManagementUrl: "https://sci-bbb.wiregene.com",
    accountManagementLabel: "SCI BBB AI 자체 계정",
    accountPolicy: "SCI BBB AI ID/PW는 해당 서비스에서 자체 관리하고 Portal은 연결만 담당합니다.",
  },
  {
    id: "human",
    label: "ARIM Human",
    shortLabel: "Human",
    url: "https://arim.wiregene.com",
    identityOwner: "subsite",
    accountManagementUrl: "https://arim.wiregene.com",
    accountManagementLabel: "ARIM Human 자체 계정",
    accountPolicy: "ARIM Human ID/PW는 ARIM 서비스에서 자체 관리하고 Portal은 연결만 담당합니다.",
  },
] as const;

export type PortalSiteId = (typeof portalSites)[number]["id"];
export type PortalRole = "admin" | "user";

export type PortalAccount = {
  id: string;
  username: string;
  email: string;
  role: PortalRole;
  sites: PortalSiteId[];
  passwordHash: string;
  mustChangePassword: boolean;
  disabled: boolean;
  createdAt: string;
  updatedAt: string;
};

export type PortalSiteCredential = {
  id: string;
  siteId: PortalSiteId;
  username: string;
  email: string;
  label: string;
  passwordHash: string;
  passwordUpdatedAt: string;
  disabled: boolean;
  createdAt: string;
  updatedAt: string;
};

type PortalAccountData = {
  accounts: PortalAccount[];
  siteCredentials: PortalSiteCredential[];
};

export type PortalAccountSummary = Omit<PortalAccount, "passwordHash"> & {
  passwordConfigured: boolean;
  source: "PORTAL_ACCOUNTS";
};

export type PortalSiteCredentialSummary = Omit<PortalSiteCredential, "passwordHash"> & {
  passwordConfigured: boolean;
  source: "SITE_CREDENTIALS";
};

export type VerifiedPortalCredential =
  | PortalAccountSummary
  | (PortalSiteCredentialSummary & {
      role: "user";
      sites: PortalSiteId[];
      mustChangePassword: false;
    });

const portalAccountStorage = createGrantJsonStorage<PortalAccountData>({
  envName: "PORTAL_ACCOUNT_STORAGE_PATH",
  defaultRelativePath: ".data/portal-accounts.json",
  label: "portal account",
  backendEnvNames: portalAccountStorageBackendEnvNames(),
  defaultBackend: "local-json",
  localReadOnlyMessage:
    "Portal account storage is locked away from Vercel Google Drive primary mode. Production ID/PW storage must run on Synology with local-json; Google Drive is backup-only unless PORTAL_ALLOW_VERCEL_GOOGLE_DRIVE_PRIMARY=true is deliberately set for a time-boxed emergency.",
  googleDriveBackup: {
    enabledEnvName: "PORTAL_ACCOUNT_GOOGLE_DRIVE_BACKUP",
    fileNameEnvName: "PORTAL_ACCOUNT_GOOGLE_DRIVE_BACKUP_FILENAME",
    fileIdEnvName: "PORTAL_ACCOUNT_GOOGLE_DRIVE_BACKUP_FILE_ID",
    defaultFileName: "portal-accounts.synology-backup.json",
  },
  emptyData: () => ({ accounts: [], siteCredentials: [] }),
  normalize: normalizePortalAccountData,
});

function portalAccountStorageBackendEnvNames() {
  const configuredBackend = process.env.PORTAL_ACCOUNT_STORAGE_BACKEND?.trim().toLowerCase();
  if (process.env.VERCEL && configuredBackend === "google-drive" && !allowVercelGoogleDrivePrimary) {
    return [];
  }

  return ["PORTAL_ACCOUNT_STORAGE_BACKEND"];
}

export function portalSiteIds() {
  return portalSites.map((site) => site.id);
}

export function portalAccountStorageWriteReadiness() {
  return portalAccountStorage.writeReadiness();
}

export async function backupPortalAccountStorageToGoogleDrive() {
  return portalAccountStorage.backupNow();
}

export async function listPortalAccountSummaries() {
  const data = await portalAccountStorage.read();
  return data.accounts
    .map(toAccountSummary)
    .sort((left, right) => left.username.localeCompare(right.username));
}

export async function listPortalSiteCredentialSummaries() {
  const data = await portalAccountStorage.read();
  return data.siteCredentials
    .map(toSiteCredentialSummary)
    .sort((left, right) => {
      const siteComparison = left.siteId.localeCompare(right.siteId);
      return siteComparison || left.username.localeCompare(right.username);
    });
}

export async function createPortalAccount(input: {
  username: string;
  email?: string;
  role?: PortalRole;
  sites?: string[];
  password?: string;
}) {
  const data = await portalAccountStorage.read();
  const username = normalizeUsername(input.username);
  const password = normalizePasswordInput(input.password);
  assertManualPortalPasswordPolicy(password);

  if (!username) throw new Error("Username is required.");
  if (data.accounts.some((account) => account.username.toLowerCase() === username.toLowerCase())) {
    throw new Error(`Account already exists: ${username}`);
  }

  const now = new Date().toISOString();
  const generatedPassword = password ? undefined : generateTemporaryPassword();
  const temporaryPassword = password || generatedPassword;
  const role = normalizeAccountRole(username, input.role);
  if (!temporaryPassword) throw new Error("Password is required.");
  const account: PortalAccount = {
    id: crypto.randomUUID(),
    username,
    email: normalizeEmail(input.email),
    role,
    sites: normalizeAccountSites(username, role, input.sites),
    passwordHash: await hashPassword(temporaryPassword),
    mustChangePassword: true,
    disabled: false,
    createdAt: now,
    updatedAt: now,
  };

  data.accounts.push(account);
  await portalAccountStorage.write(data);

  return {
    account: toAccountSummary(account),
    temporaryPassword,
    generatedPassword: Boolean(generatedPassword),
  };
}

export async function deletePortalAccount(accountId: string) {
  const data = await portalAccountStorage.read();
  const nextAccounts = data.accounts.filter((account) => account.id !== accountId);
  if (nextAccounts.length === data.accounts.length) throw new Error("Account not found.");

  data.accounts = nextAccounts;
  await portalAccountStorage.write(data);

  return { deleted: true };
}

export async function resetPortalAccountPassword(accountId: string) {
  const data = await portalAccountStorage.read();
  const account = data.accounts.find((candidate) => candidate.id === accountId);
  if (!account) throw new Error("Account not found.");

  const temporaryPassword = generateTemporaryPassword();
  account.passwordHash = await hashPassword(temporaryPassword);
  account.mustChangePassword = true;
  account.updatedAt = new Date().toISOString();

  await portalAccountStorage.write(data);

  return {
    account: toAccountSummary(account),
    temporaryPassword,
  };
}

export async function updatePortalAccount(input: {
  accountId: string;
  username?: string;
  email?: string;
  role?: PortalRole;
  sites?: string[];
  disabled?: boolean;
}) {
  const data = await portalAccountStorage.read();
  const account = data.accounts.find((candidate) => candidate.id === input.accountId);
  if (!account) throw new Error("Account not found.");

  const username = normalizeUsername(input.username ?? account.username);
  if (!username) throw new Error("Username is required.");
  if (
    data.accounts.some(
      (candidate) =>
        candidate.id !== account.id && candidate.username.toLowerCase() === username.toLowerCase(),
    )
  ) {
    throw new Error(`Account already exists: ${username}`);
  }

  const role = normalizeAccountRole(username, input.role ?? account.role);
  account.username = username;
  account.email = normalizeEmail(input.email ?? account.email);
  account.role = role;
  account.sites = normalizeAccountSites(username, role, input.sites ?? account.sites);
  account.disabled = typeof input.disabled === "boolean" ? input.disabled : account.disabled;
  account.updatedAt = new Date().toISOString();

  await portalAccountStorage.write(data);

  return {
    account: toAccountSummary(account),
  };
}

export async function createPortalSiteCredential(input: {
  siteId?: string;
  username?: string;
  email?: string;
  label?: string;
  password?: string;
}) {
  const data = await portalAccountStorage.read();
  const siteId = normalizeSiteId(input.siteId);
  const username = normalizeUsername(input.username);
  const password = normalizePasswordInput(input.password);
  assertManualSitePasswordPolicy(password);
  const generatedPassword = password ? undefined : generateTemporaryPassword();
  const effectivePassword = password || generatedPassword;

  if (!siteId) throw new Error("Site is required.");
  if (!username) throw new Error("Site username is required.");
  if (!effectivePassword) throw new Error("Password is required.");
  if (
    data.siteCredentials.some(
      (credential) =>
        credential.siteId === siteId &&
        credential.username.toLowerCase() === username.toLowerCase(),
    )
  ) {
    throw new Error(`Site credential already exists: ${siteId}/${username}`);
  }

  const now = new Date().toISOString();
  const credential: PortalSiteCredential = {
    id: crypto.randomUUID(),
    siteId,
    username,
    email: normalizeEmail(input.email),
    label: normalizeFreeText(input.label, 120),
    passwordHash: await hashPassword(effectivePassword),
    passwordUpdatedAt: now,
    disabled: false,
    createdAt: now,
    updatedAt: now,
  };

  data.siteCredentials.push(credential);
  await portalAccountStorage.write(data);

  return {
    siteCredential: toSiteCredentialSummary(credential),
    temporaryPassword: generatedPassword,
    generatedPassword: Boolean(generatedPassword),
  };
}

export async function setPortalSiteCredentialPassword(input: {
  siteCredentialId?: string;
  password?: string;
}) {
  const data = await portalAccountStorage.read();
  const credential = data.siteCredentials.find((candidate) => candidate.id === input.siteCredentialId);
  if (!credential) throw new Error("Site credential not found.");

  const password = normalizePasswordInput(input.password);
  assertManualSitePasswordPolicy(password);
  const generatedPassword = password ? undefined : generateTemporaryPassword();
  const effectivePassword = password || generatedPassword;
  const now = new Date().toISOString();

  if (!effectivePassword) throw new Error("Password is required.");

  if (await verifyPassword(effectivePassword, credential.passwordHash)) {
    throw new Error(
      "New site ID PW is the same as the current PW. Enter a different PW, or leave PW blank to generate a new strong PW.",
    );
  }

  credential.passwordHash = await hashPassword(effectivePassword);
  credential.passwordUpdatedAt = now;
  credential.updatedAt = now;

  await portalAccountStorage.write(data);

  return {
    siteCredential: toSiteCredentialSummary(credential),
    temporaryPassword: generatedPassword,
    generatedPassword: Boolean(generatedPassword),
  };
}

export async function deletePortalSiteCredential(siteCredentialId: string) {
  const data = await portalAccountStorage.read();
  const nextCredentials = data.siteCredentials.filter((credential) => credential.id !== siteCredentialId);
  if (nextCredentials.length === data.siteCredentials.length) throw new Error("Site credential not found.");

  data.siteCredentials = nextCredentials;
  await portalAccountStorage.write(data);

  return { deleted: true };
}

export async function verifyPortalAccountCredentials(input: {
  username: string;
  password: string;
  site: string;
}): Promise<VerifiedPortalCredential | null> {
  const data = await portalAccountStorage.read();
  const username = normalizeUsername(input.username);
  const site = normalizeSiteId(input.site);
  if (!site) return null;

  const account = data.accounts.find(
    (candidate) => candidate.username.toLowerCase() === username.toLowerCase(),
  );

  if (account && !account.disabled && account.sites.includes(site)) {
    const verified = await verifyPassword(input.password, account.passwordHash);
    if (verified) return toAccountSummary(account);
  }

  const siteCredential = data.siteCredentials.find(
    (candidate) =>
      candidate.siteId === site &&
      !candidate.disabled &&
      candidate.username.toLowerCase() === username.toLowerCase(),
  );
  if (!siteCredential) return null;

  const verified = await verifyPassword(input.password, siteCredential.passwordHash);
  if (!verified) return null;

  return {
    ...toSiteCredentialSummary(siteCredential),
    role: "user",
    sites: [siteCredential.siteId],
    mustChangePassword: false,
  };
}

function normalizePortalAccountData(value: unknown): PortalAccountData {
  const partial = typeof value === "object" && value !== null ? (value as Partial<PortalAccountData>) : {};
  const accounts = Array.isArray(partial.accounts) ? partial.accounts : [];
  const siteCredentials = Array.isArray(partial.siteCredentials) ? partial.siteCredentials : [];

  return {
    accounts: accounts.flatMap((account) => normalizePortalAccount(account)),
    siteCredentials: siteCredentials.flatMap((credential) => normalizePortalSiteCredential(credential)),
  };
}

function normalizePortalAccount(value: unknown): PortalAccount[] {
  if (typeof value !== "object" || value === null) return [];
  const account = value as Partial<PortalAccount>;
  const username = normalizeUsername(account.username);
  const passwordHash = typeof account.passwordHash === "string" ? account.passwordHash : "";
  if (!username || !passwordHash) return [];

  const now = new Date().toISOString();
  const role = normalizeAccountRole(username, account.role);
  return [
    {
      id: typeof account.id === "string" && account.id ? account.id : crypto.randomUUID(),
      username,
      email: normalizeEmail(account.email),
      role,
      sites: normalizeAccountSites(username, role, account.sites),
      passwordHash,
      mustChangePassword: Boolean(account.mustChangePassword),
      disabled: Boolean(account.disabled),
      createdAt: typeof account.createdAt === "string" ? account.createdAt : now,
      updatedAt: typeof account.updatedAt === "string" ? account.updatedAt : now,
    },
  ];
}

function normalizePortalSiteCredential(value: unknown): PortalSiteCredential[] {
  if (typeof value !== "object" || value === null) return [];
  const credential = value as Partial<PortalSiteCredential>;
  const siteId = normalizeSiteId(credential.siteId);
  const username = normalizeUsername(credential.username);
  const passwordHash = typeof credential.passwordHash === "string" ? credential.passwordHash : "";
  if (!siteId || !username || !passwordHash) return [];

  const now = new Date().toISOString();
  const updatedAt = typeof credential.updatedAt === "string" ? credential.updatedAt : now;
  return [
    {
      id: typeof credential.id === "string" && credential.id ? credential.id : crypto.randomUUID(),
      siteId,
      username,
      email: normalizeEmail(credential.email),
      label: normalizeFreeText(credential.label, 120),
      passwordHash,
      passwordUpdatedAt:
        typeof credential.passwordUpdatedAt === "string" ? credential.passwordUpdatedAt : updatedAt,
      disabled: Boolean(credential.disabled),
      createdAt: typeof credential.createdAt === "string" ? credential.createdAt : now,
      updatedAt,
    },
  ];
}

function toAccountSummary(account: PortalAccount): PortalAccountSummary {
  const { passwordHash: _passwordHash, ...summary } = account;
  return {
    ...summary,
    passwordConfigured: Boolean(_passwordHash),
    source: "PORTAL_ACCOUNTS",
  };
}

function toSiteCredentialSummary(credential: PortalSiteCredential): PortalSiteCredentialSummary {
  const { passwordHash: _passwordHash, ...summary } = credential;
  return {
    ...summary,
    passwordConfigured: Boolean(_passwordHash),
    source: "SITE_CREDENTIALS",
  };
}

function normalizeUsername(value: unknown) {
  return typeof value === "string" ? value.trim().replace(/\s+/g, "_").slice(0, 64) : "";
}

function normalizeEmail(value: unknown) {
  return normalizeFreeText(value, 160);
}

function normalizeAccountRole(username: string, role: unknown): PortalRole {
  if (sharedSearchOnlyPortalUsernames.has(username.toLowerCase())) return "user";
  return role === "admin" ? "admin" : "user";
}

function normalizeAccountSites(username: string, role: PortalRole, sites: unknown): PortalSiteId[] {
  if (sharedSearchOnlyPortalUsernames.has(username.toLowerCase())) return ["search"];
  return role === "admin" ? portalSiteIds() : normalizeSites(sites);
}

function normalizePasswordInput(value: unknown) {
  return typeof value === "string" ? value : "";
}

function assertManualSitePasswordPolicy(password: string) {
  if (!password) return;
  if (password.length < manualSitePasswordMinimumLength) {
    throw new Error(
      `Manual site passwords must be at least ${manualSitePasswordMinimumLength} characters. Leave PW blank to generate a strong password automatically.`,
    );
  }
  if (password.trim() !== password || /[\r\n]/.test(password)) {
    throw new Error("Manual site passwords cannot start/end with whitespace or include line breaks.");
  }
}

function assertManualPortalPasswordPolicy(password: string) {
  if (!password) return;
  if (password.length < manualPortalPasswordMinimumLength) {
    throw new Error(`Initial portal passwords must be at least ${manualPortalPasswordMinimumLength} characters.`);
  }
  if (password.trim() !== password || /[\r\n]/.test(password)) {
    throw new Error("Initial portal passwords cannot start/end with whitespace or include line breaks.");
  }
}

function normalizeFreeText(value: unknown, maxLength: number) {
  return typeof value === "string" ? value.trim().replace(/\s+/g, " ").slice(0, maxLength) : "";
}

function normalizeSiteId(value: unknown): PortalSiteId | "" {
  const allowed = new Set(portalSiteIds());
  return typeof value === "string" && allowed.has(value as PortalSiteId) ? (value as PortalSiteId) : "";
}

function normalizeSites(value: unknown): PortalSiteId[] {
  const allowed = new Set(portalSiteIds());
  const requested = Array.isArray(value) ? value : ["portal"];
  const sites = requested.filter((site): site is PortalSiteId => typeof site === "string" && allowed.has(site as PortalSiteId));
  if (sites.includes("search") && !sites.includes("omni")) sites.push("omni");
  return Array.from(new Set<PortalSiteId>(["portal", ...sites]));
}

async function hashPassword(password: string) {
  const salt = crypto.randomBytes(16).toString("base64url");
  const derived = (await scrypt(password, salt, 64)) as Buffer;
  return `scrypt:${salt}:${derived.toString("base64url")}`;
}

async function verifyPassword(password: string, passwordHash: string) {
  const [scheme, salt, expectedValue] = passwordHash.split(":");
  if (scheme !== "scrypt" || !salt || !expectedValue) return false;

  const expected = Buffer.from(expectedValue, "base64url");
  const derived = (await scrypt(password, salt, expected.length)) as Buffer;

  return expected.length === derived.length && crypto.timingSafeEqual(expected, derived);
}

function generateTemporaryPassword() {
  return `Wg-${crypto.randomBytes(12).toString("base64url")}`;
}
