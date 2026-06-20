# Portal 응급 로그인 복구

`portal.wiregene.com`에서 `rhhyun` 로그인이 되지 않으면 현재 접속 경로가 Synology인지 Vercel인지 먼저 확인합니다.

```powershell
curl.exe -I https://portal.wiregene.com/
```

응답에 `Server: Vercel` 또는 `X-Vercel-Id`가 있으면 Synology `.env`가 아니라 Vercel production env가 로그인에 사용됩니다.

## 자동 임시 비밀번호 발급

아래 명령은 Vercel production `APP_BASIC_AUTH_USERS`를 다시 설정하고 production redeploy와 로그인 확인까지 수행합니다.

```powershell
cd C:\Users\rhhyu\Documents\Portal.wiregene.com
git pull --ff-only origin main
npm.cmd run vercel:repair-portal-login -- -GeneratePassword -Redeploy
```

보안 원칙:

- `rhhyun`만 Portal 관리자 목록에 들어갑니다.
- `wiregene`은 `APP_BASIC_AUTH_SITE_ACCESS=wiregene=search`로 제한됩니다.
- `wiregene`으로 `portal.wiregene.com`에 들어갈 수 있으면 복구 실패로 봅니다.
- Search 외 다른 서브사이트는 Portal에서 사이트별 ID/PW를 만들고, 변경된 PW로만 운영합니다.

생성된 비밀번호는 채팅이나 Vercel 로그에 출력하지 않고 로컬 `.codex-logs\portal-emergency-login-*.txt` 파일에 저장됩니다.

## 직접 정한 비밀번호 사용

직접 비밀번호를 정하려면 `-GeneratePassword`를 빼고 실행합니다.

```powershell
npm.cmd run vercel:repair-portal-login -- -Redeploy
```

프롬프트에서 최소 16자 이상의 비밀번호를 입력합니다.

## 주의

- 이 작업은 `wiregene-portal` Vercel project의 production env만 수정합니다.
- 기존 Vercel sensitive env 값은 다시 읽을 수 없으므로 기존 `APP_BASIC_AUTH_USERS`에 append하지 않고 응급 계정 목록을 새로 설정합니다.
- 장기 운영 원칙은 Synology local-json 원본 + Google Drive 백업 미러입니다. 자세한 절차는 `docs/portal-synology-primary-google-drive-backup-ko.md`를 따릅니다.
