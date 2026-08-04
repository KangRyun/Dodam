import type {
  AuthProviderId,
  ProviderToken,
} from "@/features/auth/domain/auth-models";

/**
 * 서버 전용: Authorization Code를 제공자 토큰으로 교환한다.
 *
 * Kakao는 웹에서 클라이언트 토큰 발급이 폐지되어(JS SDK v2) code→token 교환이
 * 필수이며, 이 교환은 CORS 때문에 서버(Route Handler)에서만 가능하다.
 * Google·Naver는 브라우저 JS SDK로 토큰을 직접 받으므로 이 경로를 쓰지 않지만,
 * 서버-교환 방식을 함께 유지해 3사 흐름을 통일할 수도 있다.
 *
 * - Kakao·Naver: `access_token`을 백엔드의 `accessToken`으로 보낸다.
 * - Google: `id_token`을 백엔드의 `idToken`으로 보낸다.
 */

class OAuthConfigError extends Error {}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new OAuthConfigError(`${name} 환경변수가 설정되지 않았습니다.`);
  return value;
}

/**
 * Client ID(공개값)를 반환한다.
 *
 * ⚠️ 반드시 **정적** `process.env.NEXT_PUBLIC_*` 참조여야 한다. Next.js 는 빌드 시
 *    이 형태만 리터럴로 인라인한다. `process.env[변수]` 같은 동적 접근은 인라인되지
 *    않고 런타임 env 에 의존하는데, standalone 배포 파드에는 NEXT_PUBLIC_* 이 런타임
 *    env 로 없어 undefined 가 된다(dev 는 .env.local 을 런타임 로드해 우연히 동작 →
 *    이 버그가 배포에서만 터졌다. S15P11B209-817).
 */
function clientId(provider: AuthProviderId): string {
  const value =
    provider === "kakao"
      ? process.env.NEXT_PUBLIC_KAKAO_CLIENT_ID
      : provider === "google"
        ? process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID
        : process.env.NEXT_PUBLIC_NAVER_CLIENT_ID;
  if (!value) {
    throw new OAuthConfigError(
      `NEXT_PUBLIC_${provider.toUpperCase()}_CLIENT_ID 환경변수가 설정되지 않았습니다.`,
    );
  }
  return value;
}

async function postForm(
  url: string,
  form: Record<string, string>,
): Promise<Record<string, unknown>> {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(form).toString(),
  });
  const body = (await response.json()) as Record<string, unknown>;
  if (!response.ok || typeof body.error === "string") {
    const detail =
      typeof body.error_description === "string"
        ? body.error_description
        : typeof body.error === "string"
          ? body.error
          : `status ${response.status}`;
    throw new Error(`제공자 토큰 교환 실패: ${detail}`);
  }
  return body;
}

export async function exchangeCodeForProviderToken(input: {
  provider: AuthProviderId;
  code: string;
  redirectUri: string;
  state: string;
}): Promise<ProviderToken> {
  const { provider, code, redirectUri, state } = input;

  if (provider === "kakao") {
    const body = await postForm("https://kauth.kakao.com/oauth/token", {
      grant_type: "authorization_code",
      client_id: clientId("kakao"),
      ...(process.env.KAKAO_CLIENT_SECRET
        ? { client_secret: process.env.KAKAO_CLIENT_SECRET }
        : {}),
      redirect_uri: redirectUri,
      code,
    });
    return { accessToken: String(body.access_token) };
  }

  if (provider === "naver") {
    const body = await postForm("https://nid.naver.com/oauth2.0/token", {
      grant_type: "authorization_code",
      client_id: clientId("naver"),
      client_secret: requireEnv("NAVER_CLIENT_SECRET"),
      code,
      state,
    });
    return { accessToken: String(body.access_token) };
  }

  const body = await postForm("https://oauth2.googleapis.com/token", {
    grant_type: "authorization_code",
    client_id: clientId("google"),
    client_secret: requireEnv("GOOGLE_CLIENT_SECRET"),
    redirect_uri: redirectUri,
    code,
  });
  return { idToken: String(body.id_token) };
}
