import { toSession, type OAuthLoginResultDto } from "@/features/auth/data/auth-dto";
import {
  getOrCreateDeviceId,
  saveAuthProvider,
} from "@/features/auth/data/session-store";
import type {
  AuthProviderId,
  AuthSession,
} from "@/features/auth/domain/auth-models";
import {
  buildAuthorizeUrl,
  buildRedirectUri,
} from "@/features/auth/oauth/oauth-config";

/**
 * 브라우저 소셜 로그인 흐름.
 *
 * 1) {@link startOAuthLogin}: state를 만들어 저장하고 제공자 인가 화면으로 이동.
 * 2) 콜백에서 {@link completeOAuthLogin}: state를 검증하고, 서버 Route Handler
 *    (`/api/oauth/{provider}`)에 code를 넘겨 세션을 받는다. provider 토큰·secret은
 *    브라우저를 거치지 않는다.
 */
const STATE_STORAGE_KEY = "dodam.oauthState";

type SavedState = { provider: AuthProviderId; state: string };

export function startOAuthLogin(provider: AuthProviderId): void {
  const origin = window.location.origin;
  const state = createState();
  const saved: SavedState = { provider, state };
  window.sessionStorage.setItem(STATE_STORAGE_KEY, JSON.stringify(saved));
  window.location.assign(buildAuthorizeUrl(provider, origin, state));
}

/**
 * 콜백에서 로그인을 마무리한다.
 *
 * @throws 저장된 state와 일치하지 않거나(위조 방지) 서버가 실패를 반환하면 예외.
 */
export async function completeOAuthLogin(input: {
  provider: AuthProviderId;
  code: string;
  state: string;
}): Promise<AuthSession> {
  const saved = readAndClearState();
  if (
    saved == null ||
    saved.provider !== input.provider ||
    saved.state !== input.state
  ) {
    throw new Error("로그인 요청을 확인하지 못했어요. 다시 시도해 주세요.");
  }

  const redirectUri = buildRedirectUri(input.provider, window.location.origin);
  const deviceId = getOrCreateDeviceId();

  const response = await fetch(`/api/oauth/${input.provider}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      code: input.code,
      redirectUri,
      deviceId,
      state: input.state,
    }),
  });

  const text = await response.text();
  const body: unknown = text.length > 0 ? JSON.parse(text) : null;
  if (!response.ok) {
    const message =
      typeof (body as { message?: unknown })?.message === "string"
        ? (body as { message: string }).message
        : "로그인에 실패했어요. 다시 시도해 주세요.";
    throw new Error(message);
  }

  // 백엔드가 연결 제공자를 내려주지 않아, 설정 "계정 연결" 표시용으로 보관한다.
  saveAuthProvider(input.provider);
  return toSession(body as OAuthLoginResultDto);
}

function readAndClearState(): SavedState | null {
  try {
    const raw = window.sessionStorage.getItem(STATE_STORAGE_KEY);
    window.sessionStorage.removeItem(STATE_STORAGE_KEY);
    if (raw == null) return null;
    const parsed = JSON.parse(raw) as SavedState;
    return parsed;
  } catch {
    return null;
  }
}

function createState(): string {
  const globalCrypto = globalThis.crypto;
  if (globalCrypto?.randomUUID) return globalCrypto.randomUUID();
  return Math.random().toString(36).slice(2) + Date.now().toString(36);
}
