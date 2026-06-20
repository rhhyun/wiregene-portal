"use client";

import {
  Check,
  Database,
  KeyRound,
  ListChecks,
  Pencil,
  Plus,
  RefreshCw,
  RotateCcw,
  Save,
  Trash2,
  Users,
  X,
} from "lucide-react";
import type { FormEvent, ReactNode } from "react";
import { useEffect, useMemo, useState } from "react";

type PortalSite = {
  id: string;
  label: string;
  shortLabel: string;
  url: string;
};

type AccountSource = "APP_BASIC_AUTH_USER" | "APP_BASIC_AUTH_USERS" | "PORTAL_ACCOUNTS";

type AccountSummary = {
  id?: string;
  username: string;
  email?: string;
  role?: "admin" | "user";
  sites?: string[];
  source: AccountSource;
  passwordConfigured: boolean;
  mustChangePassword?: boolean;
  disabled?: boolean;
  createdAt?: string;
  updatedAt?: string;
};

type SiteCredentialSummary = {
  id: string;
  siteId: string;
  username: string;
  email?: string;
  label?: string;
  source: "SITE_CREDENTIALS";
  passwordConfigured: boolean;
  passwordUpdatedAt?: string;
  disabled?: boolean;
  createdAt?: string;
  updatedAt?: string;
};

type SiteAccount = Pick<
  AccountSummary,
  "id" | "username" | "email" | "role" | "source" | "passwordConfigured" | "mustChangePassword" | "disabled"
>;

type SiteAccountList = PortalSite & {
  count: number;
  accounts: SiteAccount[];
};

type SiteCredentialList = PortalSite & {
  count: number;
  credentials: SiteCredentialSummary[];
};

type AccountState = {
  status: "loading" | "ready" | "error";
  accounts: AccountSummary[];
  sites: PortalSite[];
  siteAccountLists: SiteAccountList[];
  siteCredentials: SiteCredentialSummary[];
  siteCredentialLists: SiteCredentialList[];
  message?: string;
  warning?: string;
  notice?: string;
  managedBy?: string;
  writable?: boolean;
};

type ApiErrorDetails = {
  label?: string;
  operation?: string;
  path?: string;
  backend?: string;
  code?: string;
  message?: string;
  cause?: string;
  backupPath?: string;
  runtime?: string;
};

type AccountApiPayload = {
  accounts?: AccountSummary[];
  sites?: PortalSite[];
  siteAccountLists?: SiteAccountList[];
  siteCredentials?: SiteCredentialSummary[];
  siteCredentialLists?: SiteCredentialList[];
  managedBy?: string;
  writable?: boolean;
  account?: AccountSummary;
  siteCredential?: SiteCredentialSummary;
  temporaryPassword?: string;
  generatedPassword?: boolean;
  deleted?: boolean;
  error?: string;
  details?: ApiErrorDetails;
  portalAccountStorageError?: ApiErrorDetails;
};

type TemporaryPasswordState = {
  label: string;
  username: string;
  password: string;
} | null;

type AccountEditDraft = {
  username: string;
  email: string;
  role: "admin" | "user";
  sites: string[];
  disabled: boolean;
};

export function AccountManagementPanel() {
  const [state, setState] = useState<AccountState>({
    status: "loading",
    accounts: [],
    sites: [],
    siteAccountLists: [],
    siteCredentials: [],
    siteCredentialLists: [],
  });
  const [username, setUsername] = useState("");
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<"admin" | "user">("user");
  const defaultUserSites = useMemo(
    () => ["portal", "omni", "protocol", "search"].filter((siteId) => state.sites.some((site) => site.id === siteId)),
    [state.sites],
  );
  const [selectedSites, setSelectedSites] = useState<string[]>(["portal", "omni", "protocol", "search"]);
  const [siteForm, setSiteForm] = useState({
    siteId: "omni",
    username: "",
    email: "",
    label: "",
    password: "",
  });
  const [credentialDrafts, setCredentialDrafts] = useState<Record<string, string>>({});
  const [accountDrafts, setAccountDrafts] = useState<Record<string, AccountEditDraft>>({});
  const [editingAccountId, setEditingAccountId] = useState<string | null>(null);
  const [temporaryPassword, setTemporaryPassword] = useState<TemporaryPasswordState>(null);
  const [submitting, setSubmitting] = useState(false);
  const [siteSubmitting, setSiteSubmitting] = useState(false);
  const [updatingAccountId, setUpdatingAccountId] = useState<string | null>(null);
  const [updatingCredentialId, setUpdatingCredentialId] = useState<string | null>(null);
  const [deletingId, setDeletingId] = useState<string | null>(null);

  const managedAccounts = useMemo(
    () => state.accounts.filter((account) => account.source === "PORTAL_ACCOUNTS"),
    [state.accounts],
  );
  const siteCredentialLists = useMemo(() => {
    if (state.siteCredentialLists.length) return state.siteCredentialLists;
    return buildSiteCredentialLists(state.sites, state.siteCredentials);
  }, [state.siteCredentialLists, state.siteCredentials, state.sites]);

  async function reloadAccounts(notice?: string) {
    setState((current) => ({ ...current, status: "loading", message: undefined, warning: undefined, notice }));
    const nextState = await getAccountState();
    setState({ ...nextState, notice });
  }

  async function createAccount(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setTemporaryPassword(null);

    try {
      const response = await fetch("/api/admin/accounts", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ kind: "portal-account", username, email, role, sites: selectedSites }),
      });
      const payload = await readAccountApiPayload(response);

      if (!response.ok || !payload.account || !payload.temporaryPassword) {
        throw new Error(formatApiError(payload.error || `HTTP ${response.status}`, payload.details));
      }

      setUsername("");
      setEmail("");
      setRole("user");
      setSelectedSites(defaultUserSites.length ? defaultUserSites : ["portal"]);
      setTemporaryPassword({
        label: "Portal 계정",
        username: payload.account.username,
        password: payload.temporaryPassword,
      });
      await reloadAccounts("Portal 계정을 생성했습니다.");
    } catch (error) {
      setState((current) => ({
        ...current,
        status: "error",
        message: error instanceof Error ? error.message : "Account creation failed.",
      }));
    } finally {
      setSubmitting(false);
    }
  }

  async function createSiteCredential(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSiteSubmitting(true);
    setTemporaryPassword(null);

    try {
      const response = await fetch("/api/admin/accounts", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ kind: "site-credential", ...siteForm }),
      });
      const payload = await readAccountApiPayload(response);

      if (!response.ok || !payload.siteCredential) {
        throw new Error(formatApiError(payload.error || `HTTP ${response.status}`, payload.details));
      }

      setSiteForm((current) => ({
        ...current,
        username: "",
        email: "",
        label: "",
        password: "",
      }));
      if (payload.temporaryPassword) {
        setTemporaryPassword({
          label: `${siteLabel(payload.siteCredential.siteId, state.sites)} 사이트 ID`,
          username: payload.siteCredential.username,
          password: payload.temporaryPassword,
        });
      }
      await reloadAccounts("사이트 ID를 저장했습니다.");
    } catch (error) {
      setState((current) => ({
        ...current,
        status: "error",
        message: error instanceof Error ? error.message : "Site credential creation failed.",
      }));
    } finally {
      setSiteSubmitting(false);
    }
  }

  function buildAccountDraft(account: AccountSummary): AccountEditDraft {
    const allSiteIds = state.sites.map((site) => site.id);
    const currentSites = account.sites?.length ? account.sites : ["portal"];

    return {
      username: account.username,
      email: account.email ?? "",
      role: account.role === "admin" ? "admin" : "user",
      sites: account.role === "admin" ? allSiteIds : Array.from(new Set(["portal", ...currentSites])),
      disabled: Boolean(account.disabled),
    };
  }

  function beginEditAccount(account: AccountSummary) {
    if (!account.id) return;
    setAccountDrafts((current) => ({
      ...current,
      [account.id as string]: current[account.id as string] ?? buildAccountDraft(account),
    }));
    setEditingAccountId(account.id);
  }

  function cancelEditAccount(accountId: string) {
    setEditingAccountId((current) => (current === accountId ? null : current));
    setAccountDrafts((current) => {
      const next = { ...current };
      delete next[accountId];
      return next;
    });
  }

  function updateAccountDraft(accountId: string, patch: Partial<AccountEditDraft>) {
    setAccountDrafts((current) => {
      const draft = current[accountId];
      if (!draft) return current;
      return {
        ...current,
        [accountId]: { ...draft, ...patch },
      };
    });
  }

  function changeAccountDraftRole(accountId: string, nextRole: "admin" | "user") {
    setAccountDrafts((current) => {
      const draft = current[accountId];
      if (!draft) return current;
      const allSiteIds = state.sites.map((site) => site.id);
      const fallbackSites = ["portal", "omni", "protocol", "search"].filter((siteId) => allSiteIds.includes(siteId));
      return {
        ...current,
        [accountId]: {
          ...draft,
          role: nextRole,
          sites: nextRole === "admin" ? allSiteIds : Array.from(new Set(["portal", ...(draft.sites.length ? draft.sites : fallbackSites)])),
        },
      };
    });
  }

  function toggleAccountDraftSite(accountId: string, siteId: string) {
    setAccountDrafts((current) => {
      const draft = current[accountId];
      if (!draft || draft.role === "admin") return current;
      if (siteId === "portal") {
        return { ...current, [accountId]: { ...draft, sites: Array.from(new Set(["portal", ...draft.sites])) } };
      }

      const sites = draft.sites.includes(siteId)
        ? draft.sites.filter((item) => item !== siteId)
        : [...draft.sites, siteId];

      return {
        ...current,
        [accountId]: { ...draft, sites: Array.from(new Set(["portal", ...sites])) },
      };
    });
  }

  async function saveAccount(account: AccountSummary) {
    if (!account.id) return;
    const draft = accountDrafts[account.id] ?? buildAccountDraft(account);
    setUpdatingAccountId(account.id);

    try {
      const response = await fetch("/api/admin/accounts", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          accountId: account.id,
          action: "update-account",
          username: draft.username,
          email: draft.email,
          role: draft.role,
          sites: draft.sites,
          disabled: draft.disabled,
        }),
      });
      const payload = await readAccountApiPayload(response);

      if (!response.ok || !payload.account) {
        throw new Error(formatApiError(payload.error || `HTTP ${response.status}`, payload.details));
      }

      cancelEditAccount(account.id);
      await reloadAccounts("Portal 계정을 변경했습니다.");
    } catch (error) {
      setState((current) => ({
        ...current,
        status: "error",
        message: error instanceof Error ? error.message : "Account update failed.",
      }));
    } finally {
      setUpdatingAccountId(null);
    }
  }

  async function resetPassword(account: AccountSummary) {
    if (!account.id) return;
    setTemporaryPassword(null);

    try {
      const response = await fetch("/api/admin/accounts", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ accountId: account.id, action: "reset-password" }),
      });
      const payload = await readAccountApiPayload(response);

      if (!response.ok || !payload.account || !payload.temporaryPassword) {
        throw new Error(formatApiError(payload.error || `HTTP ${response.status}`, payload.details));
      }

      setTemporaryPassword({
        label: "Portal 계정",
        username: payload.account.username,
        password: payload.temporaryPassword,
      });
      await reloadAccounts("Portal 계정 PW를 재발급했습니다.");
    } catch (error) {
      setState((current) => ({
        ...current,
        status: "error",
        message: error instanceof Error ? error.message : "Password reset failed.",
      }));
    }
  }

  async function deleteAccount(account: AccountSummary) {
    if (!account.id) return;
    if (!window.confirm(`${account.username} Portal 계정을 삭제할까요?`)) return;

    setDeletingId(account.id);
    try {
      const response = await fetch("/api/admin/accounts", {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ kind: "portal-account", accountId: account.id }),
      });
      const payload = await readAccountApiPayload(response);
      if (!response.ok) {
        throw new Error(formatApiError(payload.error || `HTTP ${response.status}`, payload.details));
      }
      await reloadAccounts("Portal 계정을 삭제했습니다.");
    } catch (error) {
      setState((current) => ({
        ...current,
        status: "error",
        message: error instanceof Error ? error.message : "Account deletion failed.",
      }));
    } finally {
      setDeletingId(null);
    }
  }

  async function changeSiteCredentialPassword(credential: SiteCredentialSummary) {
    setTemporaryPassword(null);
    setUpdatingCredentialId(credential.id);

    try {
      const response = await fetch("/api/admin/accounts", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          siteCredentialId: credential.id,
          action: "set-site-credential-password",
          password: credentialDrafts[credential.id] ?? "",
        }),
      });
      const payload = await readAccountApiPayload(response);

      if (!response.ok || !payload.siteCredential) {
        throw new Error(formatApiError(payload.error || `HTTP ${response.status}`, payload.details));
      }

      if (payload.temporaryPassword) {
        setTemporaryPassword({
          label: `${siteLabel(payload.siteCredential.siteId, state.sites)} 사이트 ID`,
          username: payload.siteCredential.username,
          password: payload.temporaryPassword,
        });
      }
      setCredentialDrafts((current) => ({ ...current, [credential.id]: "" }));
      await reloadAccounts("사이트 ID PW를 변경했습니다.");
    } catch (error) {
      setState((current) => ({
        ...current,
        status: "error",
        message: error instanceof Error ? error.message : "Site credential password change failed.",
      }));
    } finally {
      setUpdatingCredentialId(null);
    }
  }

  async function deleteSiteCredential(credential: SiteCredentialSummary) {
    if (!window.confirm(`${siteLabel(credential.siteId, state.sites)} / ${credential.username} ID를 삭제할까요?`)) return;

    setDeletingId(credential.id);
    try {
      const response = await fetch("/api/admin/accounts", {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ kind: "site-credential", siteCredentialId: credential.id }),
      });
      const payload = await readAccountApiPayload(response);
      if (!response.ok) {
        throw new Error(formatApiError(payload.error || `HTTP ${response.status}`, payload.details));
      }
      await reloadAccounts("사이트 ID를 삭제했습니다.");
    } catch (error) {
      setState((current) => ({
        ...current,
        status: "error",
        message: error instanceof Error ? error.message : "Site credential deletion failed.",
      }));
    } finally {
      setDeletingId(null);
    }
  }

  useEffect(() => {
    let mounted = true;

    void getAccountState().then((nextState) => {
      if (mounted) setState(nextState);
    });

    return () => {
      mounted = false;
    };
  }, []);

  function toggleSite(siteId: string) {
    setSelectedSites((current) => {
      if (siteId === "portal") return current.includes("portal") ? current : ["portal", ...current];
      if (current.includes(siteId)) return current.filter((item) => item !== siteId);
      return [...current, siteId];
    });
  }

  function changeRole(nextRole: "admin" | "user") {
    setRole(nextRole);
    if (nextRole === "admin") {
      setSelectedSites(state.sites.map((site) => site.id));
    }
  }

  return (
    <div className="grid gap-6">
      <section className="rounded-lg border border-zinc-200 bg-white p-5">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
          <div>
            <p className="text-sm font-semibold text-emerald-700">Access Control</p>
            <h2 className="mt-1 text-2xl font-semibold tracking-normal text-zinc-950">ID 관리</h2>
            <p className="mt-2 text-sm leading-6 text-zinc-600">
              Portal 로그인 계정과 사이트별 실제 접근 ID를 분리해서 관리합니다.
            </p>
          </div>
          <button
            type="button"
            onClick={() => void reloadAccounts()}
            className="inline-flex h-10 items-center justify-center gap-2 rounded-md border border-zinc-300 bg-white px-4 text-sm font-semibold text-zinc-700 transition hover:border-emerald-200 hover:bg-emerald-50 hover:text-emerald-700"
          >
            <RefreshCw className="h-4 w-4" aria-hidden />
            새로고침
          </button>
        </div>
      </section>

      <section className="grid gap-4 md:grid-cols-3">
        <StatusTile
          icon={<Users className="h-4 w-4" aria-hidden />}
          label="Portal 계정"
          value={`${managedAccounts.length}명`}
        />
        <StatusTile
          icon={<KeyRound className="h-4 w-4" aria-hidden />}
          label="사이트별 ID"
          value={`${state.siteCredentials.length}개`}
        />
        <StatusTile
          icon={<ListChecks className="h-4 w-4" aria-hidden />}
          label="서브사이트"
          value={`${siteCredentialLists.length}개`}
        />
      </section>

      <SiteCredentialListSection
        siteCredentialLists={siteCredentialLists}
        status={state.status}
        writable={Boolean(state.writable)}
        drafts={credentialDrafts}
        deletingId={deletingId}
        updatingCredentialId={updatingCredentialId}
        onDraftChange={(credentialId, value) =>
          setCredentialDrafts((current) => ({ ...current, [credentialId]: value }))
        }
        onPasswordChange={(credential) => void changeSiteCredentialPassword(credential)}
        onDelete={(credential) => void deleteSiteCredential(credential)}
      />

      {temporaryPassword ? (
        <section className="rounded-lg border border-emerald-200 bg-emerald-50 p-5">
          <p className="text-sm font-semibold text-emerald-800">임시 비밀번호 발급 완료</p>
          <div className="mt-3 grid gap-3 md:grid-cols-[12rem_1fr]">
            <InfoLine label="구분" value={temporaryPassword.label} />
            <InfoLine label="ID" value={temporaryPassword.username} />
            <InfoLine label="Temporary PW" value={temporaryPassword.password} strong />
          </div>
        </section>
      ) : null}

      {state.notice ? (
        <p className="rounded-md border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm font-medium text-emerald-900">
          {state.notice}
        </p>
      ) : null}

      {state.message ? (
        <p className="rounded-md border border-rose-200 bg-rose-50 px-4 py-3 text-sm font-medium text-rose-900">
          {state.message}
        </p>
      ) : null}

      {state.warning ? (
        <p className="rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm font-medium text-amber-900">
          {state.warning}
        </p>
      ) : null}

      {state.writable ? (
        <section className="rounded-lg border border-zinc-200 bg-white p-5">
          <h3 className="text-lg font-semibold text-zinc-950">사이트별 ID 등록</h3>
          <form onSubmit={createSiteCredential} className="mt-4 grid gap-4">
            <div className="grid gap-4 lg:grid-cols-[14rem_1fr_1fr]">
              <label className="grid gap-2 text-sm font-semibold text-zinc-700">
                Site
                <select
                  value={siteForm.siteId}
                  onChange={(event) => setSiteForm((current) => ({ ...current, siteId: event.target.value }))}
                  className="h-10 rounded-md border border-zinc-300 bg-white px-3 text-sm font-normal outline-none focus:border-emerald-400"
                >
                  {state.sites.map((site) => (
                    <option key={site.id} value={site.id}>
                      {site.shortLabel}
                    </option>
                  ))}
                </select>
              </label>
              <label className="grid gap-2 text-sm font-semibold text-zinc-700">
                ID
                <input
                  value={siteForm.username}
                  onChange={(event) => setSiteForm((current) => ({ ...current, username: event.target.value }))}
                  required
                  className="h-10 rounded-md border border-zinc-300 px-3 text-sm font-normal outline-none focus:border-emerald-400"
                  placeholder="site-user"
                />
              </label>
              <label className="grid gap-2 text-sm font-semibold text-zinc-700">
                PW
                <input
                  value={siteForm.password}
                  onChange={(event) => setSiteForm((current) => ({ ...current, password: event.target.value }))}
                  type="password"
                  className="h-10 rounded-md border border-zinc-300 px-3 text-sm font-normal outline-none focus:border-emerald-400"
                  placeholder="12자 이상 또는 자동"
                />
              </label>
            </div>

            <div className="grid gap-4 lg:grid-cols-2">
              <label className="grid gap-2 text-sm font-semibold text-zinc-700">
                Email
                <input
                  value={siteForm.email}
                  onChange={(event) => setSiteForm((current) => ({ ...current, email: event.target.value }))}
                  type="email"
                  className="h-10 rounded-md border border-zinc-300 px-3 text-sm font-normal outline-none focus:border-emerald-400"
                  placeholder="name@example.com"
                />
              </label>
              <label className="grid gap-2 text-sm font-semibold text-zinc-700">
                Label
                <input
                  value={siteForm.label}
                  onChange={(event) => setSiteForm((current) => ({ ...current, label: event.target.value }))}
                  className="h-10 rounded-md border border-zinc-300 px-3 text-sm font-normal outline-none focus:border-emerald-400"
                  placeholder="관리 메모"
                />
              </label>
            </div>

            <button
              type="submit"
              disabled={siteSubmitting}
              className="inline-flex h-11 w-fit items-center justify-center gap-2 rounded-md bg-emerald-700 px-4 text-sm font-semibold text-white transition hover:bg-emerald-800 disabled:cursor-not-allowed disabled:bg-zinc-300"
            >
              <Plus className="h-4 w-4" aria-hidden />
              {siteSubmitting ? "저장 중" : "사이트 ID 생성"}
            </button>
          </form>
        </section>
      ) : null}

      {state.writable ? (
        <section className="rounded-lg border border-zinc-200 bg-white p-5">
          <h3 className="text-lg font-semibold text-zinc-950">Portal 계정 등록</h3>
          <form onSubmit={createAccount} className="mt-4 grid gap-4">
            <div className="grid gap-4 lg:grid-cols-[1fr_1fr_10rem]">
              <label className="grid gap-2 text-sm font-semibold text-zinc-700">
                ID
                <input
                  value={username}
                  onChange={(event) => setUsername(event.target.value)}
                  required
                  className="h-10 rounded-md border border-zinc-300 px-3 text-sm font-normal outline-none focus:border-emerald-400"
                  placeholder="wiregene-user"
                />
              </label>
              <label className="grid gap-2 text-sm font-semibold text-zinc-700">
                Email
                <input
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                  type="email"
                  className="h-10 rounded-md border border-zinc-300 px-3 text-sm font-normal outline-none focus:border-emerald-400"
                  placeholder="name@example.com"
                />
              </label>
              <label className="grid gap-2 text-sm font-semibold text-zinc-700">
                Role
                <select
                  value={role}
                  onChange={(event) => changeRole(event.target.value === "admin" ? "admin" : "user")}
                  className="h-10 rounded-md border border-zinc-300 bg-white px-3 text-sm font-normal outline-none focus:border-emerald-400"
                >
                  <option value="user">사용자</option>
                  <option value="admin">관리자</option>
                </select>
              </label>
            </div>

            <div>
              <p className="text-sm font-semibold text-zinc-700">접근 가능한 사이트</p>
              <div className="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-5">
                {state.sites.map((site) => {
                  const checked = selectedSites.includes(site.id);
                  return (
                    <button
                      key={site.id}
                      type="button"
                      onClick={() => toggleSite(site.id)}
                      className={`flex h-11 items-center justify-between rounded-md border px-3 text-sm font-semibold transition ${
                        checked
                          ? "border-emerald-300 bg-emerald-50 text-emerald-800"
                          : "border-zinc-300 bg-white text-zinc-700 hover:border-emerald-200"
                      }`}
                    >
                      {site.shortLabel}
                      {checked ? <Check className="h-4 w-4" aria-hidden /> : null}
                    </button>
                  );
                })}
              </div>
            </div>

            <button
              type="submit"
              disabled={submitting}
              className="inline-flex h-11 w-fit items-center justify-center gap-2 rounded-md bg-emerald-700 px-4 text-sm font-semibold text-white transition hover:bg-emerald-800 disabled:cursor-not-allowed disabled:bg-zinc-300"
            >
              <Plus className="h-4 w-4" aria-hidden />
              {submitting ? "등록 중" : "Portal ID 생성"}
            </button>
          </form>
        </section>
      ) : null}

      <section className="rounded-lg border border-zinc-200 bg-white p-5">
        <div className="flex items-center justify-between gap-3">
          <h3 className="text-lg font-semibold text-zinc-950">Portal 접근 권한 목록</h3>
          <span
            className={`rounded-md px-2.5 py-1 text-xs font-semibold ${
              state.status === "error"
                ? "bg-rose-50 text-rose-700"
                : state.status === "loading"
                  ? "bg-zinc-100 text-zinc-600"
                  : "bg-emerald-50 text-emerald-700"
            }`}
          >
            {state.status === "error" ? "오류" : state.status === "loading" ? "확인 중" : "정상"}
          </span>
        </div>

        {state.accounts.length ? (
          <div className="mt-4 grid gap-3">
            {state.accounts.map((account) => {
              const draft = account.id ? accountDrafts[account.id] : undefined;
              const isEditing = Boolean(account.id && editingAccountId === account.id && draft);

              return (
                <div
                  key={`${account.source}:${account.id ?? account.username}`}
                  className="grid gap-3 rounded-lg border border-zinc-200 px-4 py-3 lg:grid-cols-[1fr_auto]"
                >
                  <div className="min-w-0">
                    <AccountHeading account={account} />
                    {account.email ? <p className="mt-1 text-xs text-zinc-500">{account.email}</p> : null}
                    <div className="mt-2 flex flex-wrap gap-1.5">
                      {(account.sites ?? []).map((siteId) => (
                        <span key={siteId} className="rounded-full bg-emerald-50 px-2 py-1 text-xs font-semibold text-emerald-700">
                          {siteLabel(siteId, state.sites)}
                        </span>
                      ))}
                    </div>
                  </div>
                  {state.writable && account.source === "PORTAL_ACCOUNTS" ? (
                    <div className="flex flex-wrap items-center gap-2 lg:justify-end">
                      <button
                        type="button"
                        onClick={() => beginEditAccount(account)}
                        className="inline-flex h-9 items-center justify-center gap-2 rounded-md border border-zinc-300 bg-white px-3 text-xs font-semibold text-zinc-700 transition hover:border-emerald-300 hover:bg-emerald-50"
                      >
                        <Pencil className="h-3.5 w-3.5" aria-hidden />
                        ID 변경
                      </button>
                      <button
                        type="button"
                        onClick={() => void resetPassword(account)}
                        className="inline-flex h-9 items-center justify-center gap-2 rounded-md border border-zinc-300 bg-white px-3 text-xs font-semibold text-zinc-700 transition hover:border-emerald-300 hover:bg-emerald-50"
                      >
                        <RotateCcw className="h-3.5 w-3.5" aria-hidden />
                        PW 재발급
                      </button>
                      <button
                        type="button"
                        disabled={deletingId === account.id}
                        onClick={() => void deleteAccount(account)}
                        className="inline-flex h-9 items-center justify-center gap-2 rounded-md border border-rose-200 bg-white px-3 text-xs font-semibold text-rose-700 transition hover:bg-rose-50 disabled:cursor-not-allowed disabled:text-zinc-400"
                      >
                        <Trash2 className="h-3.5 w-3.5" aria-hidden />
                        삭제
                      </button>
                    </div>
                  ) : null}

                  {isEditing && account.id && draft ? (
                    <div className="grid gap-4 border-t border-zinc-100 pt-4 lg:col-span-2">
                      <div className="grid gap-4 lg:grid-cols-[1fr_1fr_10rem_auto]">
                        <label className="grid gap-2 text-sm font-semibold text-zinc-700">
                          ID
                          <input
                            value={draft.username}
                            onChange={(event) => updateAccountDraft(account.id as string, { username: event.target.value })}
                            className="h-10 rounded-md border border-zinc-300 px-3 text-sm font-normal outline-none focus:border-emerald-400"
                          />
                        </label>
                        <label className="grid gap-2 text-sm font-semibold text-zinc-700">
                          Email
                          <input
                            value={draft.email}
                            onChange={(event) => updateAccountDraft(account.id as string, { email: event.target.value })}
                            type="email"
                            className="h-10 rounded-md border border-zinc-300 px-3 text-sm font-normal outline-none focus:border-emerald-400"
                          />
                        </label>
                        <label className="grid gap-2 text-sm font-semibold text-zinc-700">
                          Role
                          <select
                            value={draft.role}
                            onChange={(event) => changeAccountDraftRole(account.id as string, event.target.value === "admin" ? "admin" : "user")}
                            className="h-10 rounded-md border border-zinc-300 bg-white px-3 text-sm font-normal outline-none focus:border-emerald-400"
                          >
                            <option value="user">사용자</option>
                            <option value="admin">관리자</option>
                          </select>
                        </label>
                        <label className="flex items-center gap-2 self-end text-sm font-semibold text-zinc-700">
                          <input
                            checked={draft.disabled}
                            onChange={(event) => updateAccountDraft(account.id as string, { disabled: event.target.checked })}
                            type="checkbox"
                            className="h-4 w-4 rounded border-zinc-300 text-emerald-700 focus:ring-emerald-500"
                          />
                          비활성
                        </label>
                      </div>

                      <div>
                        <p className="text-sm font-semibold text-zinc-700">접근 가능한 사이트</p>
                        <div className="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-5">
                          {state.sites.map((site) => {
                            const checked = draft.sites.includes(site.id);
                            return (
                              <button
                                key={site.id}
                                type="button"
                                disabled={draft.role === "admin"}
                                onClick={() => toggleAccountDraftSite(account.id as string, site.id)}
                                className={`flex h-11 items-center justify-between rounded-md border px-3 text-sm font-semibold transition disabled:cursor-not-allowed ${
                                  checked
                                    ? "border-emerald-300 bg-emerald-50 text-emerald-800"
                                    : "border-zinc-300 bg-white text-zinc-700 hover:border-emerald-200"
                                }`}
                              >
                                {site.shortLabel}
                                {checked ? <Check className="h-4 w-4" aria-hidden /> : null}
                              </button>
                            );
                          })}
                        </div>
                      </div>

                      <div className="flex flex-wrap gap-2">
                        <button
                          type="button"
                          disabled={updatingAccountId === account.id}
                          onClick={() => void saveAccount(account)}
                          className="inline-flex h-10 items-center justify-center gap-2 rounded-md bg-emerald-700 px-4 text-sm font-semibold text-white transition hover:bg-emerald-800 disabled:cursor-not-allowed disabled:bg-zinc-300"
                        >
                          <Save className="h-4 w-4" aria-hidden />
                          저장
                        </button>
                        <button
                          type="button"
                          onClick={() => cancelEditAccount(account.id as string)}
                          className="inline-flex h-10 items-center justify-center gap-2 rounded-md border border-zinc-300 bg-white px-4 text-sm font-semibold text-zinc-700 transition hover:border-emerald-300 hover:bg-emerald-50"
                        >
                          <X className="h-4 w-4" aria-hidden />
                          취소
                        </button>
                      </div>
                    </div>
                  ) : null}
                </div>
              );
            })}
          </div>
        ) : state.status === "loading" ? (
          <p className="mt-4 text-sm text-zinc-500">계정 정보를 불러오는 중입니다.</p>
        ) : (
          <p className="mt-4 text-sm text-zinc-500">등록된 계정이 없습니다.</p>
        )}
      </section>
    </div>
  );
}

function SiteCredentialListSection({
  siteCredentialLists,
  status,
  writable,
  drafts,
  deletingId,
  updatingCredentialId,
  onDraftChange,
  onPasswordChange,
  onDelete,
}: {
  siteCredentialLists: SiteCredentialList[];
  status: AccountState["status"];
  writable: boolean;
  drafts: Record<string, string>;
  deletingId: string | null;
  updatingCredentialId: string | null;
  onDraftChange: (credentialId: string, value: string) => void;
  onPasswordChange: (credential: SiteCredentialSummary) => void;
  onDelete: (credential: SiteCredentialSummary) => void;
}) {
  return (
    <section className="grid gap-4">
      <div className="flex items-center gap-3">
        <span className="inline-flex h-10 w-10 items-center justify-center rounded-md bg-emerald-50 text-emerald-700 ring-1 ring-emerald-100">
          <Database className="h-4 w-4" aria-hidden />
        </span>
        <div>
          <p className="text-sm font-semibold text-emerald-700">Subsite ID List</p>
          <h3 className="text-xl font-semibold tracking-normal text-zinc-950">서브사이트별 실제 ID</h3>
        </div>
      </div>

      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
        {siteCredentialLists.map((site) => (
          <div key={site.id} className="rounded-lg border border-zinc-200 bg-white p-4">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="text-xs font-semibold uppercase text-emerald-700">{site.shortLabel}</p>
                <h4 className="mt-1 truncate text-base font-semibold text-zinc-950">{site.label}</h4>
                <p className="mt-1 truncate text-xs text-zinc-500">{formatDomain(site.url)}</p>
              </div>
              <span className="shrink-0 rounded-md bg-zinc-100 px-2.5 py-1 text-xs font-semibold text-zinc-700">
                {site.count} IDs
              </span>
            </div>

            {site.credentials.length ? (
              <div className="mt-4 divide-y divide-zinc-100">
                {site.credentials.map((credential) => (
                  <div key={credential.id} className="grid gap-3 py-3 first:pt-0 last:pb-0">
                    <SiteCredentialHeading credential={credential} />
                    {credential.email || credential.label ? (
                      <p className="truncate text-xs text-zinc-500">
                        {[credential.email, credential.label].filter(Boolean).join(" · ")}
                      </p>
                    ) : null}
                    {writable ? (
                      <div className="grid gap-2 sm:grid-cols-[1fr_auto_auto]">
                        <input
                          value={drafts[credential.id] ?? ""}
                          onChange={(event) => onDraftChange(credential.id, event.target.value)}
                          type="password"
                          className="h-9 min-w-0 rounded-md border border-zinc-300 px-3 text-xs outline-none focus:border-emerald-400"
                          placeholder="12자 이상 또는 자동"
                        />
                        <button
                          type="button"
                          disabled={updatingCredentialId === credential.id}
                          onClick={() => onPasswordChange(credential)}
                          className="inline-flex h-9 items-center justify-center gap-2 rounded-md border border-zinc-300 bg-white px-3 text-xs font-semibold text-zinc-700 transition hover:border-emerald-300 hover:bg-emerald-50 disabled:cursor-not-allowed disabled:text-zinc-400"
                        >
                          <KeyRound className="h-3.5 w-3.5" aria-hidden />
                          PW 변경
                        </button>
                        <button
                          type="button"
                          disabled={deletingId === credential.id}
                          onClick={() => onDelete(credential)}
                          className="inline-flex h-9 items-center justify-center gap-2 rounded-md border border-rose-200 bg-white px-3 text-xs font-semibold text-rose-700 transition hover:bg-rose-50 disabled:cursor-not-allowed disabled:text-zinc-400"
                        >
                          <Trash2 className="h-3.5 w-3.5" aria-hidden />
                          삭제
                        </button>
                      </div>
                    ) : null}
                  </div>
                ))}
              </div>
            ) : (
              <p className="mt-4 text-sm text-zinc-500">
                {status === "loading" ? "확인 중입니다." : "등록된 ID가 없습니다."}
              </p>
            )}
          </div>
        ))}
      </div>
    </section>
  );
}

async function getAccountState(): Promise<AccountState> {
  try {
    const response = await fetch("/api/admin/accounts", { cache: "no-store" });
    const payload = await readAccountApiPayload(response);

    if (!response.ok) {
      throw new Error(formatApiError(payload.error || `HTTP ${response.status}`, payload.details));
    }

    const accounts = payload.accounts ?? [];
    const sites = payload.sites ?? [];
    const siteCredentials = payload.siteCredentials ?? [];
    const warning = payload.portalAccountStorageError
      ? formatApiError("Portal 계정 저장소를 사용할 수 없습니다.", payload.portalAccountStorageError)
      : undefined;

    return {
      status: warning ? "error" : "ready",
      accounts,
      sites,
      siteAccountLists: payload.siteAccountLists ?? buildSiteAccountLists(sites, accounts),
      siteCredentials,
      siteCredentialLists: payload.siteCredentialLists ?? buildSiteCredentialLists(sites, siteCredentials),
      managedBy: payload.managedBy ?? "Vercel Environment Variables",
      writable: Boolean(payload.writable),
      warning,
    };
  } catch (error) {
    return {
      status: "error",
      accounts: [],
      sites: [],
      siteAccountLists: [],
      siteCredentials: [],
      siteCredentialLists: [],
      message: error instanceof Error ? error.message : "Unknown error",
    };
  }
}

function buildSiteAccountLists(sites: PortalSite[], accounts: AccountSummary[]): SiteAccountList[] {
  return sites.map((site) => {
    const siteAccounts = accounts
      .filter((account) => account.sites?.includes(site.id))
      .map((account) => ({
        id: account.id,
        username: account.username,
        email: account.email,
        role: account.role,
        source: account.source,
        passwordConfigured: account.passwordConfigured,
        mustChangePassword: account.mustChangePassword,
        disabled: account.disabled,
      }))
      .sort((left, right) => left.username.localeCompare(right.username));

    return {
      ...site,
      count: siteAccounts.length,
      accounts: siteAccounts,
    };
  });
}

function buildSiteCredentialLists(sites: PortalSite[], siteCredentials: SiteCredentialSummary[]): SiteCredentialList[] {
  return sites.map((site) => {
    const credentials = siteCredentials
      .filter((credential) => credential.siteId === site.id)
      .sort((left, right) => left.username.localeCompare(right.username));

    return {
      ...site,
      count: credentials.length,
      credentials,
    };
  });
}

function AccountHeading({ account, compact = false }: { account: SiteAccount; compact?: boolean }) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      <p className={`${compact ? "text-xs" : "text-sm"} font-semibold text-zinc-950`}>{account.username}</p>
      <span className="rounded-md bg-zinc-100 px-2 py-1 text-xs font-semibold text-zinc-600">
        {account.source === "PORTAL_ACCOUNTS" ? roleLabel(account.role) : sourceLabel(account.source)}
      </span>
      {account.disabled ? (
        <span className="rounded-md bg-rose-50 px-2 py-1 text-xs font-semibold text-rose-700">비활성</span>
      ) : null}
      {account.mustChangePassword ? (
        <span className="rounded-md bg-amber-50 px-2 py-1 text-xs font-semibold text-amber-700">PW 변경 필요</span>
      ) : null}
    </div>
  );
}

function SiteCredentialHeading({ credential }: { credential: SiteCredentialSummary }) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      <p className="text-sm font-semibold text-zinc-950">{credential.username}</p>
      <span className="rounded-md bg-zinc-100 px-2 py-1 text-xs font-semibold text-zinc-600">SITE ID</span>
      {credential.passwordConfigured ? (
        <span className="rounded-md bg-emerald-50 px-2 py-1 text-xs font-semibold text-emerald-700">PW 저장됨</span>
      ) : null}
      {credential.disabled ? (
        <span className="rounded-md bg-rose-50 px-2 py-1 text-xs font-semibold text-rose-700">비활성</span>
      ) : null}
    </div>
  );
}

function StatusTile({ icon, label, value }: { icon: ReactNode; label: string; value: string }) {
  return (
    <div className="rounded-lg border border-zinc-200 bg-white p-4">
      <div className="flex items-center gap-3">
        <span className="inline-flex h-9 w-9 items-center justify-center rounded-md bg-emerald-50 text-emerald-700 ring-1 ring-emerald-100">
          {icon}
        </span>
        <div className="min-w-0">
          <p className="text-sm font-medium text-zinc-500">{label}</p>
          <p className="truncate text-lg font-semibold text-zinc-950">{value}</p>
        </div>
      </div>
    </div>
  );
}

function InfoLine({ label, value, strong = false }: { label: string; value: string; strong?: boolean }) {
  return (
    <>
      <p className="text-sm font-semibold text-emerald-800">{label}</p>
      <p className={strong ? "font-mono text-sm font-semibold text-zinc-950" : "text-sm text-zinc-800"}>{value}</p>
    </>
  );
}

function siteLabel(siteId: string, sites: PortalSite[]) {
  return sites.find((site) => site.id === siteId)?.shortLabel ?? siteId;
}

function sourceLabel(source: AccountSource) {
  if (source === "APP_BASIC_AUTH_USER") return "ENV";
  if (source === "APP_BASIC_AUTH_USERS") return "ENV LIST";
  return "Portal DB";
}

function roleLabel(role: AccountSummary["role"]) {
  return role === "admin" ? "관리자" : "사용자";
}

function formatDomain(url: string) {
  return url.replace(/^https?:\/\//, "");
}

async function readAccountApiPayload(response: Response): Promise<AccountApiPayload> {
  return (await response.json().catch(() => ({ error: `HTTP ${response.status}` }))) as AccountApiPayload;
}

function formatApiError(message: string, details?: ApiErrorDetails) {
  if (!details) return message;
  if (details.code === "SERVERLESS_LOCAL_STORAGE" && details.runtime === "vercel") {
    return [
      "현재 portal.wiregene.com은 Synology가 아니라 Vercel에서 실행 중입니다.",
      "Vercel 서버는 local-json 계정 저장소에 쓸 수 없어 ID 생성이 불가능합니다.",
      "운영 원칙은 Synology local-json을 원본으로 쓰고 Google Drive는 백업 미러로 두는 것입니다.",
      "Cloudflare DNS와 DSM Reverse Proxy를 Synology로 돌린 뒤 PORTAL_ACCOUNT_STORAGE_BACKEND=local-json, PORTAL_ACCOUNT_GOOGLE_DRIVE_BACKUP=true로 운영하세요.",
      details.path ? `path=${details.path}` : undefined,
      details.backend ? `backend=${details.backend}` : undefined,
      details.runtime ? `runtime=${details.runtime}` : undefined,
    ].filter(Boolean).join(" / ");
  }

  if (details.message?.includes("Google OAuth refresh failed: invalid_client")) {
    return [
      "Portal 계정 저장소가 Google Drive 백엔드까지 도달했지만 Google OAuth Client ID/Secret이 거부되었습니다.",
      "현재 Vercel에 저장된 GOOGLE_DRIVE_CLIENT_ID 또는 GOOGLE_DRIVE_CLIENT_SECRET 값이 잘못되었거나 서로 맞지 않습니다.",
      "Vercel/GitHub의 sensitive secrets는 값을 다시 읽을 수 없으므로 Search/Meta 프로젝트에서 자동 복구할 수 없습니다.",
      "Google Cloud Console의 정확한 OAuth Client ID와 Client Secret을 확인한 뒤, 같은 쌍으로 Portal 전용 Refresh Token을 다시 발급해야 합니다.",
      "장기 운영은 Synology local-json 원본 + Google Drive 백업으로 전환하고, Vercel Google Drive 원본은 응급/임시 경로로만 사용하세요.",
      details.path ? `path=${details.path}` : undefined,
      details.operation ? `operation=${details.operation}` : undefined,
      details.backend ? `backend=${details.backend}` : undefined,
      details.runtime ? `runtime=${details.runtime}` : undefined,
    ].filter(Boolean).join(" / ");
  }

  if (details.message?.includes("Google OAuth refresh failed: invalid_grant")) {
    return [
      "Portal 계정 저장소가 Google Drive 백엔드까지 도달했지만 Refresh Token이 거부되었습니다.",
      "GOOGLE_DRIVE_REFRESH_TOKEN이 만료, 취소, 오복사되었거나 현재 OAuth Client ID/Secret 쌍으로 발급된 토큰이 아닙니다.",
      "정확한 OAuth Client ID와 Client Secret을 확인한 뒤 같은 쌍으로 Portal 전용 Refresh Token을 다시 발급해야 합니다.",
      "장기 운영은 Synology local-json 원본 + Google Drive 백업으로 전환하고, Vercel Google Drive 원본은 응급/임시 경로로만 사용하세요.",
      details.path ? `path=${details.path}` : undefined,
      details.operation ? `operation=${details.operation}` : undefined,
      details.backend ? `backend=${details.backend}` : undefined,
      details.runtime ? `runtime=${details.runtime}` : undefined,
    ].filter(Boolean).join(" / ");
  }

  const parts = [
    message,
    details.message,
    details.code ? `code=${details.code}` : undefined,
    details.path ? `path=${details.path}` : undefined,
    details.operation ? `operation=${details.operation}` : undefined,
    details.backend ? `backend=${details.backend}` : undefined,
    details.runtime ? `runtime=${details.runtime}` : undefined,
    details.cause ? `cause=${details.cause}` : undefined,
    details.backupPath ? `backup=${details.backupPath}` : undefined,
  ].filter(Boolean);

  return Array.from(new Set(parts)).join(" / ");
}
