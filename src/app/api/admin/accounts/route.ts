import { NextResponse } from "next/server";

import { getWiregeneAppMode } from "@/lib/app-mode";
import {
  findBasicAuthAccountForCredential,
  getBasicAuthAccountSummaries,
  parseBasicAuthCredential,
} from "@/lib/basic-auth-users";
import { grantStorageErrorDetails } from "@/lib/grant-storage";
import {
  createPortalAccount,
  createPortalSiteCredential,
  deletePortalAccount,
  deletePortalSiteCredential,
  listPortalAccountSummaries,
  listPortalSiteCredentialSummaries,
  portalAccountStorageWriteReadiness,
  portalSites,
  resetPortalAccountPassword,
  setPortalSiteCredentialPassword,
  updatePortalAccount,
  verifyPortalAccountCredentials,
  type PortalSiteId,
} from "@/lib/portal-accounts";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  if (!isPortalMode(request)) return portalOnlyResponse();
  if (!(await isAuthenticatedAdminRequest(request))) return authRequiredResponse();

  const mode = getWiregeneAppMode(request.headers.get("host"));
  const environmentAccounts = getBasicAuthAccountSummaries();
  const storageWriteReadiness = portalAccountStorageWriteReadiness();
  let portalAccounts: Awaited<ReturnType<typeof listPortalAccountSummaries>> = [];
  let siteCredentials: Awaited<ReturnType<typeof listPortalSiteCredentialSummaries>> = [];
  let portalAccountStorageError: ReturnType<typeof grantStorageErrorDetails> | undefined;

  try {
    [portalAccounts, siteCredentials] = await Promise.all([
      listPortalAccountSummaries(),
      listPortalSiteCredentialSummaries(),
    ]);
  } catch (error) {
    portalAccountStorageError = grantStorageErrorDetails(error);
    logPortalAccountStorageError("list", error);
  }

  const accounts = [...environmentAccounts, ...portalAccounts];

  return NextResponse.json(
    {
      accounts,
      count: accounts.length,
      sites: portalSites,
      siteAccountLists: buildSiteAccountLists(accounts),
      siteCredentials,
      siteCredentialLists: buildSiteCredentialLists(siteCredentials),
      siteCredentialCount: siteCredentials.length,
      managedBy: mode === "portal" ? "Portal account storage + Vercel Basic Auth" : "Vercel Environment Variables",
      writable: mode === "portal" && storageWriteReadiness.writable && !portalAccountStorageError,
      portalAccountStorageError: portalAccountStorageError ?? storageWriteReadiness.details,
      portalAccountStorage: storageWriteReadiness,
    },
    {
      headers: {
        "Cache-Control": "no-store",
      },
    },
  );
}

export async function POST(request: Request) {
  if (!isPortalMode(request)) return portalOnlyResponse();
  if (!(await isAuthenticatedAdminRequest(request))) return authRequiredResponse();
  if (!isTrustedMutationRequest(request)) return untrustedMutationResponse();
  const storageWriteReadiness = portalAccountStorageWriteReadiness();
  if (!storageWriteReadiness.writable) return storageNotWritableResponse(storageWriteReadiness.details);

  try {
    const payload = (await request.json()) as {
      kind?: "portal-account" | "site-credential";
      username?: string;
      email?: string;
      role?: "admin" | "user";
      sites?: string[];
      siteId?: string;
      label?: string;
      password?: string;
    };

    if (payload.kind === "site-credential") {
      if (!legacySiteCredentialWritesEnabled()) return siteCredentialDelegatedResponse();
      const result = await createPortalSiteCredential({
        siteId: payload.siteId,
        username: payload.username,
        email: payload.email,
        label: payload.label,
        password: payload.password,
      });
      return NextResponse.json(result, { status: 201 });
    }

    if (!payload.username) {
      return NextResponse.json({ error: "Username is required." }, { status: 400 });
    }
    const result = await createPortalAccount({
      username: payload.username,
      email: payload.email,
      role: payload.role,
      sites: payload.sites,
      password: payload.password,
    });
    return NextResponse.json(result, { status: 201 });
  } catch (error) {
    logPortalAccountStorageError("create", error);
    return accountErrorResponse(error);
  }
}

export async function PATCH(request: Request) {
  if (!isPortalMode(request)) return portalOnlyResponse();
  if (!(await isAuthenticatedAdminRequest(request))) return authRequiredResponse();
  if (!isTrustedMutationRequest(request)) return untrustedMutationResponse();
  const storageWriteReadiness = portalAccountStorageWriteReadiness();
  if (!storageWriteReadiness.writable) return storageNotWritableResponse(storageWriteReadiness.details);

  try {
    const payload = (await request.json()) as {
      accountId?: string;
      siteCredentialId?: string;
      action?: "reset-password" | "update-account" | "set-site-credential-password";
      password?: string;
      username?: string;
      email?: string;
      role?: "admin" | "user";
      sites?: string[];
      disabled?: boolean;
    };

    if (payload.action === "reset-password") {
      if (!payload.accountId) {
        return NextResponse.json({ error: "Account id is required." }, { status: 400 });
      }
      const result = await resetPortalAccountPassword(payload.accountId);
      return NextResponse.json(result);
    }

    if (payload.action === "update-account") {
      if (!payload.accountId) {
        return NextResponse.json({ error: "Account id is required." }, { status: 400 });
      }
      const result = await updatePortalAccount({
        accountId: payload.accountId,
        username: payload.username,
        email: payload.email,
        role: payload.role,
        sites: payload.sites,
        disabled: payload.disabled,
      });
      return NextResponse.json(result);
    }

    if (payload.action === "set-site-credential-password" && payload.siteCredentialId) {
      if (!legacySiteCredentialWritesEnabled()) return siteCredentialDelegatedResponse();
      const result = await setPortalSiteCredentialPassword({
        siteCredentialId: payload.siteCredentialId,
        password: payload.password,
      });
      return NextResponse.json(result);
    }

    return NextResponse.json({ error: "Unsupported account action." }, { status: 400 });
  } catch (error) {
    logPortalAccountStorageError("patch", error);
    return accountErrorResponse(error);
  }
}

export async function DELETE(request: Request) {
  if (!isPortalMode(request)) return portalOnlyResponse();
  if (!(await isAuthenticatedAdminRequest(request))) return authRequiredResponse();
  if (!isTrustedMutationRequest(request)) return untrustedMutationResponse();
  const storageWriteReadiness = portalAccountStorageWriteReadiness();
  if (!storageWriteReadiness.writable) return storageNotWritableResponse(storageWriteReadiness.details);

  try {
    const payload = (await request.json().catch(() => null)) as {
      kind?: "portal-account" | "site-credential";
      accountId?: string;
      siteCredentialId?: string;
    } | null;

    if (payload?.kind === "site-credential" && payload.siteCredentialId) {
      if (!legacySiteCredentialWritesEnabled()) return siteCredentialDelegatedResponse();
      return NextResponse.json(await deletePortalSiteCredential(payload.siteCredentialId));
    }

    if (payload?.kind === "portal-account" && payload.accountId) {
      return NextResponse.json(await deletePortalAccount(payload.accountId));
    }

    return NextResponse.json({ error: "Unsupported delete action." }, { status: 400 });
  } catch (error) {
    logPortalAccountStorageError("delete", error);
    return accountErrorResponse(error);
  }
}

function isPortalMode(request: Request) {
  return getWiregeneAppMode(request.headers.get("host")) === "portal";
}

function portalOnlyResponse() {
  return NextResponse.json(
    {
      error: "Writable account management is available only on portal.wiregene.com.",
    },
    { status: 403 },
  );
}

function authRequiredResponse() {
  return NextResponse.json(
    {
      error: "Portal login is required.",
    },
    {
      status: 401,
      headers: {
        "WWW-Authenticate": 'Basic realm="Wiregene Portal", charset="UTF-8"',
      },
    },
  );
}

async function isAuthenticatedAdminRequest(request: Request) {
  const providedCredential = parseBasicAuthCredential(request.headers.get("authorization") ?? "");
  if (!providedCredential) return false;

  const environmentAccount = findBasicAuthAccountForCredential(providedCredential);
  if (environmentAccount?.role === "admin" && environmentAccount.sites.includes("portal")) {
    return true;
  }

  const portalAccount = await verifyPortalAccountCredentials({
    username: providedCredential.username,
    password: providedCredential.password,
    site: "portal",
  }).catch((error) => {
    logPortalAccountStorageError("verify", error);
    return null;
  });

  return portalAccount?.source === "PORTAL_ACCOUNTS" && portalAccount.role === "admin";
}

function isTrustedMutationRequest(request: Request) {
  const secFetchSite = request.headers.get("sec-fetch-site");
  if (secFetchSite && !["none", "same-origin", "same-site"].includes(secFetchSite)) return false;

  const origin = request.headers.get("origin");
  if (!origin) return true;

  const host = request.headers.get("host");
  if (!host) return false;

  try {
    return new URL(origin).host === host;
  } catch {
    return false;
  }
}

function untrustedMutationResponse() {
  return NextResponse.json(
    {
      error: "Rejected cross-site account management request.",
    },
    { status: 403 },
  );
}

function storageNotWritableResponse(details: ReturnType<typeof portalAccountStorageWriteReadiness>["details"]) {
  return NextResponse.json(
    {
      error: details?.message ?? "Portal account storage is not writable.",
      details,
    },
    { status: 409 },
  );
}

function legacySiteCredentialWritesEnabled() {
  return process.env.PORTAL_ENABLE_LEGACY_SITE_CREDENTIALS === "true";
}

function siteCredentialDelegatedResponse() {
  return NextResponse.json(
    {
      error:
        "서브사이트 ID/PW는 이제 각 사이트에서 자체 관리합니다. Portal은 관리 위치 연결과 상태 관제만 담당합니다.",
      code: "SUBSITE_CREDENTIALS_DELEGATED",
    },
    { status: 409 },
  );
}

type AdminAccountSummary = Awaited<ReturnType<typeof listPortalAccountSummaries>>[number] | ReturnType<typeof getBasicAuthAccountSummaries>[number];
type AdminSiteCredentialSummary = Awaited<ReturnType<typeof listPortalSiteCredentialSummaries>>[number];

function buildSiteAccountLists(accounts: AdminAccountSummary[]) {
  return portalSites.map((site) => {
    const siteAccounts = accounts
      .filter((account) => account.sites?.includes(site.id))
      .map((account) => ({
        id: "id" in account ? account.id : undefined,
        username: account.username,
        email: "email" in account ? account.email : undefined,
        role: account.role,
        source: account.source,
        passwordConfigured: account.passwordConfigured,
        mustChangePassword: "mustChangePassword" in account ? account.mustChangePassword : undefined,
        disabled: "disabled" in account ? account.disabled : undefined,
      }))
      .sort((left, right) => left.username.localeCompare(right.username));

    return {
      id: site.id as PortalSiteId,
      label: site.label,
      shortLabel: site.shortLabel,
      url: site.url,
      count: siteAccounts.length,
      accounts: siteAccounts,
    };
  });
}

function buildSiteCredentialLists(siteCredentials: AdminSiteCredentialSummary[]) {
  return portalSites.map((site) => {
    const credentials = siteCredentials
      .filter((credential) => credential.siteId === site.id)
      .sort((left, right) => left.username.localeCompare(right.username));

    return {
      id: site.id as PortalSiteId,
      label: site.label,
      shortLabel: site.shortLabel,
      url: site.url,
      count: credentials.length,
      credentials,
    };
  });
}

function accountErrorResponse(error: unknown) {
  return NextResponse.json(
    {
      error: error instanceof Error ? error.message : "Account operation failed.",
      details: grantStorageErrorDetails(error),
    },
    { status: 400 },
  );
}

function logPortalAccountStorageError(context: string, error: unknown) {
  const details = grantStorageErrorDetails(error);
  console.error("[api/admin/accounts] portal account storage error", {
    context,
    details,
  });
}
