/**
 * 웹 로그인/회원가입 도메인 모델.
 *
 * 앱과 동일한 백엔드 계약(`POST /auth/oauth/{provider}`, `PUT /users/me/onboarding`,
 * `GET /consents/terms`)을 그대로 사용하므로, 같은 소셜 계정이면 앱·웹이 하나의
 * 계정을 공유한다.
 */

/** 지원하는 소셜 로그인 제공자. 백엔드 경로 `/auth/oauth/{provider}`의 소문자 값. */
export type AuthProviderId = "kakao" | "google" | "naver";

/** 온보딩에서 선택 가능한 사용자 역할. 백엔드 `UserRole` 중 ADMIN은 제외된다. */
export type UserRole = "GUARDIAN" | "EXPERT";

/** 약관 동의 행위. */
export type ConsentAction = "AGREE" | "WITHDRAW";

/** 로그인 응답에 담기는 사용자 정보. 온보딩 이전에는 role이 `null`일 수 있다. */
export type AuthUser = {
  userId: number;
  role: UserRole | null;
  nickname: string | null;
  email: string | null;
  /**
   * 추가 이메일 입력이 필요한지 여부(백엔드가 판단).
   *
   * 저장된 이메일도, 제공자 이메일도 없을 때만 `true`. provider 종류로 추론하지
   * 않고 이 값에만 의존한다(앱과 동일).
   */
  emailRequired: boolean;
  accountStatus: string;
  onboardingCompleted: boolean;
};

export type AuthTokens = {
  accessToken: string;
  refreshToken: string;
  accessTokenExpiresInSeconds: number;
  refreshTokenExpiresInSeconds: number;
};

export type AuthSession = AuthTokens & { user: AuthUser };

/** 약관 항목(`GET /consents/terms`). */
export type ConsentTerm = {
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

export type ConsentAgreement = { termId: number; action: ConsentAction };

/** 온보딩 완료 입력(`PUT /users/me/onboarding`). */
export type OnboardingInput = {
  role: UserRole;
  nickname: string;
  email: string;
  consents: ConsentAgreement[];
};

/**
 * 백엔드 `/auth/oauth/{provider}`에 전달하는 제공자 토큰.
 *
 * Kakao·Naver는 `accessToken`, Google은 `idToken`을 채운다.
 */
export type ProviderToken = { accessToken?: string; idToken?: string };
