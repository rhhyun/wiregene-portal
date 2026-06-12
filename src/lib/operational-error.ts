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
        "Vercel/GitHub sensitive secrets는 값을 다시 읽을 수 없으므로 Search/Meta에서 자동 복구할 수 없습니다. Google Cloud Console의 정확한 OAuth Client ID와 Client Secret, 그 쌍으로 발급한 Refresh Token 3개를 같은 값으로 다시 설정해야 합니다.",
    };
  }

  if (message.includes("Google OAuth refresh failed: invalid_grant")) {
    return {
      title: "Google Drive refresh token 오류",
      message:
        "Portal 계정 저장소가 Google Drive 백엔드까지 도달했지만 Refresh Token이 거부되었습니다. GOOGLE_DRIVE_REFRESH_TOKEN이 만료, 취소, 오복사되었거나 현재 OAuth Client ID/Secret 쌍으로 발급된 토큰이 아닙니다.",
      action:
        "정확한 OAuth Client ID와 Client Secret을 확인한 뒤 같은 쌍으로 Refresh Token을 다시 발급해 GitHub와 Vercel에 반영하세요.",
    };
  }

  if (message.includes("Google Drive")) {
    return {
      title: "Google Drive 연결 오류",
      message,
      action:
        "REPORT_STORAGE_BACKEND=google-drive 설정과 Google Drive OAuth 3종 값을 확인하세요. 배포 환경을 수정한 뒤에는 Vercel redeploy가 필요합니다.",
    };
  }

  return {
    title: "대시보드 데이터 로드 오류",
    message,
    action: "서버 로그와 환경변수를 확인한 뒤 다시 로드하세요.",
  };
}
