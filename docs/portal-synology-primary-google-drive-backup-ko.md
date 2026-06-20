# Portal ID/PW 저장 원칙

Portal은 Wiregene 전체 서브사이트의 ID/PW 관리 페이지이므로 운영 원본과 백업을 분리합니다.

## 원칙

- 운영 원본: Synology Docker의 local JSON 파일
- 백업 사본: Google Drive JSON 파일
- Vercel: 응급 접속 또는 임시 배포용이며, ID/PW 운영 원본으로 쓰지 않습니다.

운영 원본 파일:

```text
/volume1/docker/portal/data/portal-accounts.json
```

컨테이너 내부 경로:

```text
/app/.data/portal/portal-accounts.json
```

Google Drive 백업 기본 파일명:

```text
portal-accounts.synology-backup.json
```

이 파일에는 Portal 계정과 서브사이트별 로그인 ID/PW 해시가 들어갑니다. 평문 비밀번호를 저장하지 않고, 새 비밀번호는 생성/변경 순간에만 화면에 표시합니다.

## Synology .env 설정

`/volume1/docker/portal/.env`는 아래 구조가 원칙입니다.

```text
PORTAL_ACCOUNT_STORAGE_BACKEND=local-json
PORTAL_ACCOUNT_STORAGE_PATH=.data/portal/portal-accounts.json
PORTAL_ACCOUNT_GOOGLE_DRIVE_BACKUP=true
PORTAL_ACCOUNT_GOOGLE_DRIVE_BACKUP_FILENAME=portal-accounts.synology-backup.json

GOOGLE_DRIVE_CLIENT_ID=...
GOOGLE_DRIVE_CLIENT_SECRET=...
GOOGLE_DRIVE_REFRESH_TOKEN=...
GOOGLE_DRIVE_FOLDER_NAME=Wiregene Portal
```

앱은 local JSON 쓰기가 성공한 뒤 Google Drive 백업을 시도합니다. Google Drive 백업이 실패해도 Synology 원본 저장은 유지됩니다.

## 수동 백업

기존 파일을 즉시 Google Drive로 백업하려면 Synology에서 실행합니다.

```sh
cd /volume1/docker/wiregene-portal
/bin/sh /volume1/docker/wiregene-portal/scripts/synology-backup-portal-accounts-google-drive.sh
```

정기 작업으로는 아래 전체 업데이트 명령을 먼저 사용하고, Google Drive OAuth 값이 준비된 뒤 수동 백업 명령을 별도 작업으로 추가합니다.

```sh
cd /volume1/docker/wiregene-portal && git pull --ff-only origin main && /bin/sh /volume1/docker/wiregene-portal/scripts/synology-update-portal.sh
```

백업만 별도 정기 실행하려면 DSM 작업 스케줄러에 아래 명령을 등록합니다.

```sh
cd /volume1/docker/wiregene-portal && git pull --ff-only origin main && /bin/sh /volume1/docker/wiregene-portal/scripts/synology-backup-portal-accounts-google-drive.sh
```
