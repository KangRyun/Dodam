import { NextResponse } from "next/server";

import type { AuthProviderId } from "@/features/auth/domain/auth-models";
import { OAUTH_PROVIDERS } from "@/features/auth/oauth/oauth-config";
import { exchangeCodeForProviderToken } from "@/features/auth/oauth/oauth-token-exchange";

/**
 * 서버 전용 소셜 로그인 엔드포인트.
 *
 * Kakao처럼 브라우저에서 토큰을 직접 받을 수 없는 경우, 서버에서 code를
 * provider 토큰으로 교환하고 곧바로 앱과 동일한 백엔드
 * `POST /auth/oauth/{provider}`로 로그인한 뒤 세션을 브라우저로 돌려준다.
 */
const BACKEND_BASE_URL =
  process.env.API_BASE_URL ??
  process.env.NEXT_PUBLIC_API_BASE_URL ??
  "http://localhost:8080/api/v1";

type LoginPayload = {
  code?: unknown;
  redirectUri?: unknown;
  deviceId?: unknown;
  state?: unknown;
};

export async function POST(
  request: Request,
  { params }: { params: Promise<{ provider: string }> },
) {
  const { provider } = await params;
  if (!OAUTH_PROVIDERS.includes(provider as AuthProviderId)) {
    return NextResponse.json(
      { message: "지원하지 않는 로그인 제공자입니다." },
      { status: 400 },
    );
  }
  const providerId = provider as AuthProviderId;

  let payload: LoginPayload;
  try {
    payload = (await request.json()) as LoginPayload;
  } catch {
    return NextResponse.json(
      { message: "요청 본문을 읽지 못했습니다." },
      { status: 400 },
    );
  }

  const { code, redirectUri, deviceId, state } = payload;
  if (
    typeof code !== "string" ||
    typeof redirectUri !== "string" ||
    typeof deviceId !== "string"
  ) {
    return NextResponse.json(
      { message: "code·redirectUri·deviceId가 필요합니다." },
      { status: 400 },
    );
  }

  try {
    const token = await exchangeCodeForProviderToken({
      provider: providerId,
      code,
      redirectUri,
      state: typeof state === "string" ? state : "",
    });

    const backendResponse = await fetch(
      `${BACKEND_BASE_URL}/auth/oauth/${providerId}`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify({
          accessToken: token.accessToken ?? null,
          idToken: token.idToken ?? null,
          deviceId,
        }),
      },
    );

    const text = await backendResponse.text();
    const body: unknown = text.length > 0 ? JSON.parse(text) : null;

    if (!backendResponse.ok) {
      const message =
        isEnvelope(body) && typeof body.message === "string"
          ? body.message
          : "로그인에 실패했습니다.";
      const code = isEnvelope(body) ? body.code : undefined;
      return NextResponse.json(
        { message, code },
        { status: backendResponse.status },
      );
    }

    const data = isEnvelope(body) ? body.data : body;
    return NextResponse.json(data, { status: 200 });
  } catch (error) {
    const message =
      error instanceof Error
        ? error.message
        : "로그인 처리 중 오류가 발생했습니다.";
    return NextResponse.json({ message }, { status: 502 });
  }
}

function isEnvelope(
  body: unknown,
): body is { success: boolean; code?: string; message?: string; data: unknown } {
  return typeof body === "object" && body !== null && "data" in body;
}
