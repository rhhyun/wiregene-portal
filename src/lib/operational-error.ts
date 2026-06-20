export type OperationalError = {
  title: string;
  message: string;
  action: string;
};

export function toOperationalError(error: unknown): OperationalError {
  const message = error instanceof Error ? error.message : String(error);

  if (message.includes("Google OAuth refresh failed: invalid_client")) {
    return {
      title: "Google Drive OAuth client 설정 오류",
      message:
        "Portal 계정 저장소가 Google Drive 백엔드까지 도달했지만 Google OAuth Client ID/Secret이 거부되었습니다. Vercel에 저장된 GOOGLE_DRIVE_CLIENT_ID 또는 GOOGLE_DRIVE_CLIENT_SECRET 값이 잘못되었거나 서로 맞지 않습니다.",
      action:
        "Vercel/GitHub sensitive secrets는 값을 다시 읽을 수 없으므로 Search/Meta에서 자동 복구할 수 없습니다. 장기 운영은 Synology local-json 원본 + Google Drive 백업으로 전환하세요. Vercel Google Drive 원본은 응급/임시 경로로만 사용합니다.",
    };
  }

  if (message.includes("Google OAuth refresh failed: invalid_grant")) {
    return {
      title: "Google Drive refresh token 오류",
      message:
        "Portal 계정 저장소가 Google Drive 백엔드까지 도달했지만 Refresh Token이 거부되었습니다. GOOGLE_DRIVE_REFRESH_TOKEN이 만료, 취소, 오복사되었거나 현재 OAuth Client ID/Secret 쌍으로 발급된 토큰이 아닙니다.",
      action:
        "정확한 OAuth Client ID와 Client Secret을 확인해 백업용 Refresh Token을 발급하세요. 운영 원본은 Synology local-json에 두고, Google Drive는 PORTAL_ACCOUNT_GOOGLE_DRIVE_BACKUP=true 백업 미러로 사용합니다.",
    };
  }

  if (message.includes("Google Drive")) {
    return {
      title: "Google Drive 연결 오류",
      message,
      action:
        "Portal ID/PW 운영 원본은 Synology local-json으로 유지하고, Google Drive OAuth 3종 값은 백업 미러 설정에만 사용하세요.",
    };
  }

  return {
    title: "대시보드 데이터 로드 오류",
    message,
    action: "서버 로그와 환경변수를 확인한 뒤 다시 로드하세요.",
  };
}
