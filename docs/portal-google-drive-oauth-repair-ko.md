# Portal Google Drive OAuth 응급 복구 절차

장기 운영 원칙은 Synology local JSON을 ID/PW 원본으로 쓰고 Google Drive는 백업 미러로 두는 것입니다. 이 문서는 `portal.wiregene.com`이 임시로 Vercel에서 Google Drive를 원본 저장소로 사용할 때만 적용합니다.

`portal.wiregene.com`에서 아래 오류가 보이면 저장소 코드는 이미 Google Drive 백엔드까지 도달한 상태입니다.

```text
Google OAuth refresh failed: invalid_grant
```

이 오류는 `PORTAL_ACCOUNT_STORAGE_BACKEND=google-drive`가 적용되었지만, Vercel production에 들어 있는 `GOOGLE_DRIVE_REFRESH_TOKEN`이 현재 `GOOGLE_DRIVE_CLIENT_ID` / `GOOGLE_DRIVE_CLIENT_SECRET` 쌍으로 발급된 토큰이 아니거나, 만료/취소/오복사되었다는 뜻입니다.

## 원칙

- Vercel sensitive env 값은 생성 뒤 다시 읽을 수 없습니다. Search/Meta/Portal의 기존 secret을 자동으로 복구할 수 없습니다.
- Portal 복구에는 Google Cloud Console에서 확인한 정확한 OAuth Client ID와 Client Secret, 그리고 그 둘로 새로 발급한 Portal Refresh Token이 필요합니다.
- 다른 서브사이트가 마비되는 경우는 주로 다른 사이트의 Vercel/GitHub env를 덮어쓰거나, Google 계정에서 OAuth 앱 접근을 취소하거나, OAuth client 자체를 삭제했을 때입니다.
- Portal 복구 스크립트는 `wiregene-portal` Vercel project만 수정합니다. Search/Meta env는 건드리지 않습니다.
- 장기 운영은 `docs/portal-synology-primary-google-drive-backup-ko.md`를 따릅니다.

## 1. Portal Refresh Token 발급

PowerShell에서 `npm`이 실행 정책에 막힐 수 있으므로 `npm.cmd`를 사용합니다.

```powershell
cd C:\Users\rhhyu\Documents\Portal.wiregene.com
git pull --ff-only origin main
npm.cmd run google-drive:oauth:portal
```

프롬프트가 나오면 Google Cloud Console에서 확인한 값을 붙여넣습니다.

```text
Paste Portal GOOGLE_DRIVE_CLIENT_ID
Paste Portal GOOGLE_DRIVE_CLIENT_SECRET
```

Google 승인 화면에서 `400 오류: redirect_uri_mismatch`가 나오면, 같은 OAuth Client의 Google Cloud Console 설정에 아래 값을 Authorized redirect URI로 정확히 추가합니다.

```text
http://127.0.0.1:53682/oauth2callback
```

`http`, `127.0.0.1`, 포트 `53682`, `/oauth2callback`까지 모두 정확히 일치해야 합니다. OAuth Client 종류가 `Web application`이면 이 값이 반드시 등록되어 있어야 하고, `Desktop app`이면 일반적으로 loopback redirect가 허용됩니다.

터미널에 Google 승인 URL이 표시되면 브라우저에서 열어 승인합니다. 승인이 끝나면 터미널에 `GOOGLE_DRIVE_REFRESH_TOKEN`이 출력됩니다.

## 2. Vercel production env 반영

방금 사용한 Client ID, Client Secret, 새 Refresh Token을 같은 실행에서 붙여넣습니다.

```powershell
npm.cmd run vercel:repair-portal-google-drive
```

이 스크립트는 Vercel에 쓰기 전에 Google token endpoint에서 세 값의 조합을 먼저 검증합니다. 검증이 실패하면 Vercel env를 건드리지 않습니다.

반영되는 주요 값은 아래와 같습니다.

```text
APP_BASE_URL=https://portal.wiregene.com
WIREGENE_APP_MODE=portal
PORTAL_ACCOUNT_STORAGE_BACKEND=google-drive
PORTAL_ACCOUNT_STORAGE_PATH_DRIVE_FILENAME=portal-accounts.json
GOOGLE_DRIVE_CLIENT_ID=<same client id>
GOOGLE_DRIVE_CLIENT_SECRET=<same client secret>
GOOGLE_DRIVE_REFRESH_TOKEN=<new portal refresh token>
GOOGLE_DRIVE_FOLDER_NAME=Wiregene Portal
```

## 3. 확인

복구 스크립트는 production redeploy 후 `https://portal.wiregene.com/api/admin/storage-health`를 secret header로 호출해 `portal-accounts.json` 읽기/쓰기 상태를 확인합니다.

추가로 env 메타데이터만 확인할 때는 아래 명령을 사용합니다. secret 값은 출력되지 않습니다.

```powershell
npm.cmd run vercel:audit-google-drive-env
```

감사 결과가 `api-error`이면 Vercel CLI 로그인/팀 권한/API 응답 문제입니다. 이것을 env가 없다는 뜻으로 해석하지 않습니다.
