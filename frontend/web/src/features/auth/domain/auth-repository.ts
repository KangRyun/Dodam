import type {
  AuthProviderId,
  AuthSession,
  AuthUser,
  ConsentTerm,
  OnboardingInput,
  ProviderToken,
} from "@/features/auth/domain/auth-models";

/**
 * 로그인/온보딩 백엔드 계약을 감싸는 저장소.
 *
 * 커뮤니티의 저장소 패턴(도메인 인터페이스 + api 구현 + factory)을 그대로 따른다.
 * 앱과 동일하게 각 사 JS SDK로 브라우저에서 받은 provider 토큰을 그대로
 * 백엔드로 보낸다(서버 secret 불필요).
 */
export interface AuthRepository {
  /** provider 토큰으로 로그인/회원가입한다(`POST /auth/oauth/{provider}`). */
  signIn(input: {
    provider: AuthProviderId;
    token: ProviderToken;
    deviceId: string;
  }): Promise<AuthSession>;

  /** 리프레시 토큰으로 세션을 재발급한다(`POST /auth/reissue`). */
  reissue(input: {
    refreshToken: string;
    deviceId: string;
  }): Promise<AuthSession>;

  /** 세션을 종료한다(`POST /auth/logout`). */
  logout(input: { refreshToken: string; deviceId: string }): Promise<void>;

  /** 현재 로그인 사용자를 회원 탈퇴 처리한다(`DELETE /users/me`). */
  deleteAccount(input: {
    refreshToken: string;
    deviceId: string;
  }): Promise<void>;

  /** 동의할 약관 목록을 조회한다(`GET /consents/terms?targetScope=USER`). */
  getTerms(): Promise<ConsentTerm[]>;

  /** 기본정보·이메일·약관 동의를 저장해 온보딩을 완료한다(`PUT /users/me/onboarding`). */
  completeOnboarding(input: OnboardingInput): Promise<AuthUser>;

  /** 현재 로그인 사용자 정보를 조회한다(`GET /users/me`). */
  getMe(): Promise<AuthUser>;
}
