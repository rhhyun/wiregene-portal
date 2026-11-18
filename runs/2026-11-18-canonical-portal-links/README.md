# Portal 링크 복구 v1.7.5

2026-11-18 기준 소스는 GitHub `rhhyun/wiregene-portal`의 `main` 커밋
`59ba69addd31956f3da983c143ba6d95733c945f`에서 시작했다.

| Portal 항목 | 확인된 공식 주소 | DNS 응답이 없던 이전 주소 |
| --- | --- | --- |
| Hyun Lab | https://www.wiregene.com/hyunlab | `hyun.wiregene.com` |
| SCI BBB AI 2 | https://sci-bbb.wiregene.com | `sci-bbb-ai.wiregene.com` |

실행 화면과 계정 안내는 위 공식 주소를 사용한다. 기존 `lab-homepage`,
`behavior`, `behavior-ai` 권한 ID와 저장된 계정 설정이 계속 동작한다.
기존 표시 버전 `1.74`의 소수점 이하 두 자리를 minor와 patch로 해석하고
이번 릴리스는 `1.7.5`로 기록한다.

## 검증과 운영 차단 요인

- 공개 조사에서 Cloudflare와 Google DNS가 이전 주소 모두 NXDOMAIN을 반환했다.
  공식 주소는 각각 HTTP 200으로 렌더링됐으며 SCI BBB는 WebSocket HTTP 101도
  확인했다.
- 로컬 카탈로그 검사에서 두 항목의 실행 및 계정 안내 URL, `behavior-ai`
  레거시 권한 매핑, 버전 `1.7.5`를 확인했다.
- ESLint 경고 0개, 독립 TypeScript 검사, Next.js 운영 빌드가 통과했다.
- 로컬 운영 빌드를 임시 계정과 임시 local-json 경로로 구동했다.
  비인증 진입과 계정 API는 HTTP 401이었다. 임시 계정 인증 뒤 실행 화면과
  계정 API의 공식 주소를 검증했고 `/api/health`는 버전 `1.7.5`를 반환했다.
- `npm.cmd run verify:portal-runtime`의 런타임 정책 회귀와
  `APP_DIR="$PWD" /bin/sh scripts/verify-synology-route-policy.sh`의
  공개 라우팅 정책 회귀가 통과했다.
- 기존 스케줄러의 읽기 전용 `PORTAL_ROUTE_CHECK_ONLY=1` 검사에서
  `portal.wiregene.com`이 HTTP 401, `Server: Vercel`, `X-Vercel-Id`를
  반환해 Synology 정책이 종료 코드 1을 반환했다. 같은 호스트의
  `/api/health`는 HTTP 404다.

## 다른 PC와 Synology에서 이어서 진행

1. GitHub `rhhyun/wiregene-portal`의 `main`을 받아 `npm.cmd ci`,
   `npm.cmd run lint -- --max-warnings=0`, `npm.cmd run build`를 실행한다.
2. GitHub Actions의 **Build Portal Docker Image**가 릴리스 커밋과 일치하고
   GHCR에 해당 커밋 태그를 게시했는지 확인한다.
3. NAS의 Portal 원본과 영속 계정 저장소를 확인한다. 공개 전환 전에는
   승인된 라우팅 경로로 NAS의 Portal 응답과 계정 저장소 준비를 검증한다.
   공개 라우팅을 전환한 뒤 `portal.wiregene.com`에서 Synology 응답을 확인한다.
4. DSM **제어판 → 작업 스케줄러 → 기존 Portal 배포 작업 → 실행**을 사용한다.
   기존 작업 명령은 [DEPLOYMENT.md](../../DEPLOYMENT.md)의
   **Final DSM Task Scheduler Command**에 있다.
5. 배포 로그에서 로컬 건강 상태와 `Ver 1.7.5`를 확인한다. 공개
   `https://portal.wiregene.com/api/health`에서 버전 `1.7.5` 응답을
   확인한 뒤, 승인된 계정으로 실행 화면의 두 연결을 확인한다.
