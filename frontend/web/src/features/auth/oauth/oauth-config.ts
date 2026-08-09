import type { AuthProviderId } from "@/features/auth/domain/auth-models";

/**
 * 브라우저에서 사용하는 OAuth 설정.
 *
 * 브라우저는 네이티브 SDK를 쓸 수 없으므로 Authorization Code 리다이렉트 방식을
 * 쓴다. 여기서는 인가(authorize) 리다이렉트 URL만 만든다. code를 provider
 * 토큰으로 교환하는 단계는 client secret이 필요하므로 서버 Route Handler
 * (`/api/oauth/[provider]`)에서 처리한다.
 *
 * Client ID는 `NEXT_PUBLIC_*` 환경변수로만 받는다.
 */
export const OAUTH_PROVIDERS: readonly AuthProviderId[] = [
  "kakao",
  "google",
  "naver",
];

type ProviderClientConfig = {
  /** 제공자 인가 화면 URL. */
  authorizeUrl: string;
  /** 브라우저에 노출 가능한 Client ID(`NEXT_PUBLIC_*`). */
  clientId: string | undefined;
  /** 요청 scope. 비어 있으면 scope 파라미터를 생략한다. */
  scope: string;
};

const CLIENT_CONFIG: Record<AuthProviderId, ProviderClientConfig> = {
  kakao: {
    authorizeUrl: "https://kauth.kakao.com/oauth/authorize",
    clientId: process.env.NEXT_PUBLIC_KAKAO_CLIENT_ID,
    // 이메일 등 동의항목(scope)은 요청하지 않는다. 이 앱은 비즈 앱이 아니라
    // account_email을 요청하면 KOE205가 난다. 이메일은 온보딩에서 직접 받는다.
    scope: "",
  },
  google: {
    authorizeUrl: "https://accounts.google.com/o/oauth2/v2/auth",
    clientId: process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID,
    scope: "openid email profile",
  },
  naver: {
    authorizeUrl: "https://nid.naver.com/oauth2.0/authorize",
    clientId: process.env.NEXT_PUBLIC_NAVER_CLIENT_ID,
    scope: "",
  },
};

/** 콘솔에 등록해야 하는 리다이렉트 URI. origin 기준으로 만든다. */
export function buildRedirectUri(
  provider: AuthProviderId,
  origin: string,
): string {
  return `${origin}/login/callback/${provider}`;
}

/** 제공자 인가 화면으로 보낼 URL을 만든다. Client ID 미설정이면 예외. */
export function buildAuthorizeUrl(
  provider: AuthProviderId,
  origin: string,
  state: string,
): string {
  const config = CLIENT_CONFIG[provider];
  if (!config.clientId) {
    throw new Error(
      `${provider} Client ID가 없습니다. NEXT_PUBLIC_${provider.toUpperCase()}_CLIENT_ID를 설정해 주세요.`,
    );
  }
  const params = new URLSearchParams({
    client_id: config.clientId,
    redirect_uri: buildRedirectUri(provider, origin),
    response_type: "code",
    state,
  });
  if (config.scope) params.set("scope", config.scope);
  return `${config.authorizeUrl}?${params.toString()}`;
}

/** Client ID가 설정된 제공자인지. 미설정 제공자는 로그인 버튼을 비활성화한다. */
export function isProviderConfigured(provider: AuthProviderId): boolean {
  return Boolean(CLIENT_CONFIG[provider].clientId);
}
