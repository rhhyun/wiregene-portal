import {
  ArrowUpRight,
  BarChart3,
  BookOpenText,
  Bot,
  BrainCircuit,
  ChartCandlestick,
  FileText,
  FlaskConical,
  Globe2,
  Home,
  LayoutDashboard,
  LockKeyhole,
  Microscope,
  Music,
  ShieldCheck,
  Stethoscope,
  UserRoundCog,
  type LucideIcon,
} from "lucide-react";
import type { CurrentWiregeneUser } from "@/lib/auth-session";
import { portalSites, type PortalSiteId } from "@/lib/portal-accounts";
import { AccountManagementPanel } from "./AccountManagementPanel";

const MASTER_LOGIN_ID = "rhhyun";

const siteDisplay: Record<
  PortalSiteId,
  {
    category: string;
    description: string;
    icon: LucideIcon;
  }
> = {
  portal: {
    category: "Operations",
    description: "Wiregene 통합 로그인, ID/PW 생성, 삭제, 변경, 사이트 운영 확인",
    icon: ShieldCheck,
  },
  homepage: {
    category: "Public",
    description: "Wiregene 공개 홈페이지와 회사/연구 소개의 기본 진입점",
    icon: Home,
  },
  "homepage-admin": {
    category: "Admin",
    description: "Wiregene 홈페이지 콘텐츠와 관리자 페이지 운영",
    icon: LockKeyhole,
  },
  agi: {
    category: "AI",
    description: "AGI/Brain 메모리, 검토 콘솔, 장기 연구 운영 원칙 관리",
    icon: Bot,
  },
  search: {
    category: "Research",
    description: "논문, 뉴스, 연구과제 검색과 문헌 모니터링",
    icon: BookOpenText,
  },
  omni: {
    category: "Research",
    description: "연구 주제, 논문 작성, 메타분석 작업을 연결하는 작성 허브",
    icon: BookOpenText,
  },
  protocol: {
    category: "Research",
    description: "연구계획서, protocol, IRB 문서 작성과 방법론 비교",
    icon: FileText,
  },
  meta: {
    category: "Research",
    description: "PRISMA, 검색식, screening, extraction, analysis 관리",
    icon: BarChart3,
  },
  finance: {
    category: "Finance",
    description: "Trading Alpha Lab, market research, Finance Brain workspace",
    icon: ChartCandlestick,
  },
  music: {
    category: "AI",
    description: "MusicXML-first audio-to-score reconstruction workspace",
    icon: Music,
  },
  hyunlab: {
    category: "Operations",
    description: "연구실 ERP, 연구 운영, 과제, 구매, Journal Club 관리",
    icon: LayoutDashboard,
  },
  "lab-homepage": {
    category: "Public",
    description: "Hyun Lab 공개 홈페이지, 연구 주제, 구성원, 출판물 소개",
    icon: Globe2,
  },
  "sci-experiment": {
    category: "Experiment",
    description: "SCI 실험 데이터, 전기장 FEM, 결과 관리 보조",
    icon: FlaskConical,
  },
  behavior: {
    category: "Experiment",
    description: "SCI rat BBB 및 ladder 행동실험 영상 분석",
    icon: BrainCircuit,
  },
  "behavior-ai": {
    category: "Experiment",
    description: "SCI BBB AI 보조 도메인 및 대체 진입 링크",
    icon: BrainCircuit,
  },
  human: {
    category: "Clinical",
    description: "ARIM 재활의학 입원/외래 환자 관리와 임상 업무 지원",
    icon: Microscope,
  },
  "diabetic-foot": {
    category: "Clinical",
    description: "당뇨발 위험도 선별 및 임상 연구 데모",
    icon: Stethoscope,
  },
};

const launcherSites = portalSites.map((site) => ({
  ...site,
  ...siteDisplay[site.id],
  href: withPortalSource(site.url),
}));

export function PortalDashboard({
  currentUser,
  versionLabel,
}: {
  currentUser?: CurrentWiregeneUser | null;
  versionLabel: string;
}) {
  const canManageAccounts = Boolean(currentUser?.isAdmin);

  return (
    <main className="min-h-screen bg-zinc-50 text-zinc-950">
      <header className="border-b border-zinc-200 bg-white">
        <div className="mx-auto flex max-w-7xl flex-col gap-4 px-5 py-6 lg:flex-row lg:items-center lg:justify-between">
          <div className="flex items-center gap-3">
            <span className="inline-flex h-11 w-11 items-center justify-center rounded-md bg-emerald-50 text-emerald-700 ring-1 ring-emerald-100">
              <ShieldCheck className="h-5 w-5" aria-hidden />
            </span>
            <div>
              <p className="text-sm font-semibold text-emerald-700">Wiregene Portal</p>
              <h1 className="text-2xl font-semibold tracking-normal">통합 사이트 및 ID/PW 관리</h1>
              <p className="mt-1 text-xs font-medium text-zinc-500">{versionLabel}</p>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-3">
            <MasterLoginBadge />
            <AdminBadge currentUser={currentUser} />
            {canManageAccounts ? (
              <a
                href="#member-management"
                className="inline-flex h-10 items-center justify-center gap-2 rounded-md border border-emerald-300 bg-emerald-50 px-4 text-sm font-semibold text-emerald-800 transition hover:border-emerald-400 hover:bg-emerald-100"
              >
                회원관리
                <UserRoundCog className="h-4 w-4" aria-hidden />
              </a>
            ) : null}
          </div>
        </div>
      </header>

      <div className="mx-auto grid max-w-7xl gap-8 px-5 py-8">
        <section>
          <div className="flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="text-sm font-semibold text-emerald-700">Wiregene Sites</p>
              <h2 className="text-xl font-semibold tracking-normal">연결된 서브페이지</h2>
              <p className="mt-2 max-w-3xl text-sm leading-6 text-zinc-600">
                첫 화면에는 현재 Portal에서 관리해야 하는 Wiregene 서브페이지 링크를 먼저 표시합니다.
                각 사이트 진입용 Master ID는 {MASTER_LOGIN_ID}로 통일합니다.
              </p>
            </div>
            <div className="grid gap-2 text-sm text-zinc-600 sm:grid-cols-3 lg:min-w-[28rem]">
              <SummaryTile label="Sites" value={`${launcherSites.length}`} />
              <SummaryTile label="Master ID" value={MASTER_LOGIN_ID} />
              <SummaryTile label="Signed in" value={currentUser?.username ?? "None"} />
            </div>
          </div>

          <div className="mt-5 grid gap-3 md:grid-cols-2 xl:grid-cols-4">
            {launcherSites.map((site) => (
              <SiteCard key={site.id} site={site} />
            ))}
          </div>
        </section>

        {canManageAccounts ? (
          <section>
            <div className="mb-4 flex items-center gap-3">
              <span className="inline-flex h-10 w-10 items-center justify-center rounded-md bg-emerald-50 text-emerald-700 ring-1 ring-emerald-100">
                <UserRoundCog className="h-4 w-4" aria-hidden />
              </span>
              <div>
                <p className="text-sm font-semibold text-emerald-700">Account Management</p>
                <h2 className="text-xl font-semibold tracking-normal">ID/PW 생성 및 사이트별 계정 관리</h2>
              </div>
            </div>
            <AccountManagementPanel />
          </section>
        ) : null}
      </div>
    </main>
  );
}

function SiteCard({ site }: { site: (typeof launcherSites)[number] }) {
  const Icon = site.icon;

  return (
    <a
      href={site.href}
      className="group flex min-h-52 flex-col justify-between rounded-lg border border-zinc-200 bg-white p-4 transition hover:border-emerald-300 hover:bg-emerald-50"
    >
      <div>
        <div className="flex items-start justify-between gap-3">
          <span className="inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-md bg-zinc-100 text-zinc-700 transition group-hover:bg-white group-hover:text-emerald-700">
            <Icon className="h-4 w-4" aria-hidden />
          </span>
          <ArrowUpRight className="h-4 w-4 text-zinc-400 transition group-hover:text-emerald-700" aria-hidden />
        </div>
        <p className="mt-4 text-xs font-semibold uppercase text-emerald-700">{site.category}</p>
        <h3 className="mt-1 text-base font-semibold text-zinc-950">{site.label}</h3>
        <p className="mt-2 text-sm leading-6 text-zinc-600">{site.description}</p>
      </div>
      <div className="mt-4 flex flex-wrap items-center gap-2">
        <span className="rounded-md bg-zinc-100 px-2 py-1 text-xs font-semibold text-zinc-700">
          ID {MASTER_LOGIN_ID}
        </span>
        <span className="truncate rounded-md bg-zinc-100 px-2 py-1 text-xs font-medium text-zinc-500">
          {new URL(site.url).hostname}
        </span>
      </div>
    </a>
  );
}

function MasterLoginBadge() {
  return (
    <div className="inline-flex h-10 items-center gap-2 rounded-md border border-zinc-200 bg-zinc-50 px-3 text-sm font-semibold text-zinc-800">
      <LockKeyhole className="h-4 w-4" aria-hidden />
      <span>Master ID</span>
      <span className="text-emerald-700">{MASTER_LOGIN_ID}</span>
    </div>
  );
}

function AdminBadge({ currentUser }: { currentUser?: CurrentWiregeneUser | null }) {
  if (!currentUser?.isAdmin) return null;

  return (
    <div className="inline-flex h-10 items-center gap-2 rounded-md border border-emerald-200 bg-emerald-50 px-3 text-sm font-semibold text-emerald-800">
      <ShieldCheck className="h-4 w-4" aria-hidden />
      <span>전체관리자</span>
      <span className="max-w-48 truncate text-xs font-medium text-emerald-700">{currentUser.username}</span>
    </div>
  );
}

function SummaryTile({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border border-zinc-200 bg-white p-3">
      <p className="text-xs font-semibold uppercase text-zinc-500">{label}</p>
      <p className="mt-1 truncate text-lg font-semibold text-zinc-950">{value}</p>
    </div>
  );
}

function withPortalSource(url: string) {
  const separator = url.includes("?") ? "&" : "?";
  return `${url}${separator}wiregene_from=portal`;
}
