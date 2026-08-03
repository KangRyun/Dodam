import type {
  AuthSession,
  AuthUser,
  ConsentTerm,
  UserRole,
} from "@/features/auth/domain/auth-models";

// --- 백엔드 응답 DTO (com.ssafy.b209.auth / user / consent) ---

export type OAuthLoginUserDto = {
  userId: number;
  role: UserRole | null;
  nickname: string | null;
  email: string | null;
  emailRequired: boolean;
  accountStatus: string;
  onboardingCompleted: boolean;
};

export type OAuthLoginResultDto = {
  grantType: string;
  accessToken: string;
  accessTokenExpiresInSeconds: number;
  refreshToken: string;
  refreshTokenExpiresInSeconds: number;
  user: OAuthLoginUserDto;
};

export type UserResponseDto = {
  userId: number;
  role: UserRole | null;
  nickname: string | null;
  email: string | null;
  accountStatus: string;
  onboardingCompleted: boolean;
};

export type ConsentTermDto = {
  termId: number;
  termCode: string;
  targetScope: string;
  required: boolean;
  version: string;
  title: string;
  contentUrl: string | null;
  contentHtml: string | null;
  effectiveAt: string;
};

export function toSession(dto: OAuthLoginResultDto): AuthSession {
  return {
    accessToken: dto.accessToken,
    refreshToken: dto.refreshToken,
    accessTokenExpiresInSeconds: dto.accessTokenExpiresInSeconds,
    refreshTokenExpiresInSeconds: dto.refreshTokenExpiresInSeconds,
    user: {
      userId: dto.user.userId,
      role: dto.user.role,
      nickname: dto.user.nickname,
      email: dto.user.email,
      emailRequired: dto.user.emailRequired,
      accountStatus: dto.user.accountStatus,
      onboardingCompleted: dto.user.onboardingCompleted,
    },
  };
}

export function toUser(dto: UserResponseDto): AuthUser {
  return {
    userId: dto.userId,
    role: dto.role,
    nickname: dto.nickname,
    email: dto.email,
    // 온보딩 이후 응답에는 emailRequired가 없다 — 이미 이메일이 확정된 상태다.
    emailRequired: false,
    accountStatus: dto.accountStatus,
    onboardingCompleted: dto.onboardingCompleted,
  };
}

export function toTerm(dto: ConsentTermDto): ConsentTerm {
  return {
    termId: dto.termId,
    termCode: dto.termCode,
    targetScope: dto.targetScope,
    required: dto.required,
    version: dto.version,
    title: dto.title,
    contentUrl: dto.contentUrl,
    contentHtml: dto.contentHtml,
    effectiveAt: dto.effectiveAt,
  };
}
