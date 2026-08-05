const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080/api/v1";

/**
 * 모바일 웹뷰가 로그인 토큰을 심는 `localStorage` 키.
 *
 * 커뮤니티 웹앱은 앱 웹뷰 안에서 이 키를 읽어 백엔드를 같은 사용자로 호출한다.
 * (`community_webview_screen.dart`가 주입한다.)
 */
export const ACCESS_TOKEN_STORAGE_KEY = "dodam.accessToken";
/** 액세스 토큰 만료 시 재발급에 쓰는 리프레시 토큰 키. */
export const REFRESH_TOKEN_STORAGE_KEY = "dodam.refreshToken";
/** 재발급이 검증하는 최초 로그인 기기 식별자 키. */
export const DEVICE_ID_STORAGE_KEY = "dodam.deviceId";

/**
 * 같은 탭에서 토큰이 바뀌었을 때(재발급 성공/세션 정리) 헤더 등이 다시 읽도록
 * 발행하는 커스텀 이벤트. `storage` 이벤트는 다른 탭에서만 발생하므로 보완한다.
 */
export const AUTH_CHANGED_EVENT = "dodam:auth-changed";

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

/** 브라우저 로컬 저장소. 서버 렌더링 시점에는 `null`. */
function browserStorage(): Storage | null {
  if (typeof window === "undefined") return null;
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

function readStored(key: string): string | null {
  return browserStorage()?.getItem(key) ?? null;
}

/** 브라우저에서만 접근 가능한 로그인 토큰을 읽는다. 서버 렌더링 시점에는 `null`. */
function readAccessToken(): string | null {
  return readStored(ACCESS_TOKEN_STORAGE_KEY);
}

function dispatchAuthChanged(): void {
  if (typeof window !== "undefined") {
    window.dispatchEvent(new Event(AUTH_CHANGED_EVENT));
  }
}

/** 재발급 실패 시 만료 세션을 정리해 로그아웃 상태(헤더=로그인 버튼)로 되돌린다. */
function clearStoredSession(): void {
  const storage = browserStorage();
  if (storage == null) return;
  storage.removeItem(ACCESS_TOKEN_STORAGE_KEY);
  storage.removeItem(REFRESH_TOKEN_STORAGE_KEY);
  dispatchAuthChanged();
}

/** 재발급 응답에서 필요한 필드만 안전하게 읽기 위한 형태. */
type ReissueData = { accessToken?: unknown; refreshToken?: unknown };

/**
 * 진행 중인 재발급 Promise. 동시에 여러 요청이 401을 만나도 재발급은 **한 번만**
 * 수행하고 결과를 공유한다(single-flight). 백엔드가 리프레시 토큰을 1회용으로
 * 회전(rotation)하며 재사용을 탐지하므로, 중복 재발급은 세션 폐기로 이어진다.
 */
let reissueInFlight: Promise<boolean> | null = null;

function reissueSession(): Promise<boolean> {
  if (reissueInFlight) return reissueInFlight;
  reissueInFlight = requestReissue().finally(() => {
    reissueInFlight = null;
  });
  return reissueInFlight;
}

/**
 * 저장된 리프레시 토큰·기기 식별자로 세션을 재발급한다.
 *
 * 인터셉터 재귀를 피하려고 {@link apiRequest} 대신 원시 fetch를 쓴다. 재발급
 * 엔드포인트는 액세스 토큰이 없어도 되므로 `Authorization`을 붙이지 않는다.
 *
 * @returns 새 토큰 저장까지 성공하면 `true`.
 */
async function requestReissue(): Promise<boolean> {
  const storage = browserStorage();
  if (storage == null) return false;
  const refreshToken = storage.getItem(REFRESH_TOKEN_STORAGE_KEY);
  const deviceId = storage.getItem(DEVICE_ID_STORAGE_KEY);
  if (!refreshToken || !deviceId) return false;

  try {
    const response = await fetch(`${API_BASE_URL}/auth/reissue`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ refreshToken, deviceId }),
    });
    if (!response.ok) return false;

    const text = await response.text();
    const body: unknown = text.length > 0 ? JSON.parse(text) : null;
    const data = (isEnvelope(body) ? body.data : body) as ReissueData | null;
    const nextAccess =
      data != null && typeof data.accessToken === "string"
        ? data.accessToken
        : null;
    const nextRefresh =
      data != null && typeof data.refreshToken === "string"
        ? data.refreshToken
        : null;
    if (!nextAccess || !nextRefresh) return false;

    storage.setItem(ACCESS_TOKEN_STORAGE_KEY, nextAccess);
    storage.setItem(REFRESH_TOKEN_STORAGE_KEY, nextRefresh);
    dispatchAuthChanged();
    return true;
  } catch {
    return false;
  }
}

/**
 * 백엔드 공통 응답 봉투를 벗겨 `data`만 돌려주는 fetch 래퍼.
 *
 * - 로그인 토큰이 있으면 `Authorization: Bearer`를 자동으로 붙인다.
 * - HTTP 204(본문 없음)는 `undefined`를 반환한다.
 * - **401(액세스 토큰 만료)**: 리프레시 토큰으로 세션을 1회 재발급한 뒤 원 요청을
 *   재시도한다. 재발급이 실패하면 만료 세션을 정리하고 오류로 던진다.
 * - 실패 응답은 봉투의 `code`·`message`를 담은 {@link ApiClientError}로 던진다.
 */
export async function apiRequest<T>(
  path: string,
  init: RequestInit = {},
  options: { retryOnAuthError?: boolean } = {},
): Promise<T> {
  const { retryOnAuthError = true } = options;

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
    // 액세스 토큰 만료(401): 리프레시 토큰이 있으면 재발급 후 원 요청을 1회 재시도.
    if (
      response.status === 401 &&
      retryOnAuthError &&
      readStored(REFRESH_TOKEN_STORAGE_KEY) != null
    ) {
      const reissued = await reissueSession();
      if (reissued) {
        return apiRequest<T>(path, init, { retryOnAuthError: false });
      }
      // 재발급 실패 → 만료 세션 정리(헤더가 로그인 상태로 복귀).
      clearStoredSession();
    }

    const message =
      isEnvelope(body) && typeof body.message === "string"
        ? body.message
        : "요청을 처리하지 못했습니다.";
    const code = isEnvelope(body) ? body.code : undefined;
    throw new ApiClientError(message, response.status, code);
  }

  return (isEnvelope(body) ? body.data : body) as T;
}
