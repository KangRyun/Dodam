const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080/api/v1";

/**
 * 모바일 웹뷰가 로그인 토큰을 심는 `localStorage` 키.
 *
 * 커뮤니티 웹앱은 앱 웹뷰 안에서 이 키를 읽어 백엔드를 같은 사용자로 호출한다.
 * (`community_webview_screen.dart`가 주입한다.)
 */
export const ACCESS_TOKEN_STORAGE_KEY = "dodam.accessToken";

export class ApiClientError extends Error {
  constructor(
    message: string,
    readonly status: number,
    /** 백엔드 공통 오류 응답의 애플리케이션 코드. 없으면 `undefined`. */
    readonly code?: string,
  ) {
    super(message);
    this.name = "ApiClientError";
  }
}

/** 백엔드 공통 성공/오류 응답 봉투. 실제 payload는 `data`에 담긴다. */
type ApiEnvelope<T> = {
  success: boolean;
  code: string;
  message: string;
  data: T;
};

function isEnvelope(body: unknown): body is ApiEnvelope<unknown> {
  return (
    typeof body === "object" &&
    body !== null &&
    "success" in body &&
    "data" in body
  );
}

/** 브라우저에서만 접근 가능한 로그인 토큰을 읽는다. 서버 렌더링 시점에는 `null`. */
function readAccessToken(): string | null {
  if (typeof window === "undefined") return null;
  try {
    return window.localStorage.getItem(ACCESS_TOKEN_STORAGE_KEY);
  } catch {
    return null;
  }
}

/**
 * 백엔드 공통 응답 봉투를 벗겨 `data`만 돌려주는 fetch 래퍼.
 *
 * - 로그인 토큰이 있으면 `Authorization: Bearer`를 자동으로 붙인다.
 * - HTTP 204(본문 없음)는 `undefined`를 반환한다.
 * - 실패 응답은 봉투의 `code`·`message`를 담은 {@link ApiClientError}로 던진다.
 */
export async function apiRequest<T>(
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set("Accept", "application/json");
  if (init.body != null && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }
  const token = readAccessToken();
  if (token) headers.set("Authorization", `Bearer ${token}`);

  const response = await fetch(`${API_BASE_URL}/${path.replace(/^\/+/, "")}`, {
    ...init,
    headers,
  });

  if (response.status === 204) return undefined as T;

  const text = await response.text();
  const body: unknown = text.length > 0 ? JSON.parse(text) : null;

  if (!response.ok) {
    const message =
      isEnvelope(body) && typeof body.message === "string"
        ? body.message
        : "요청을 처리하지 못했습니다.";
    const code = isEnvelope(body) ? body.code : undefined;
    throw new ApiClientError(message, response.status, code);
  }

  return (isEnvelope(body) ? body.data : body) as T;
}
