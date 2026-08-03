import type { AuthSession } from "@/features/auth/domain/auth-models";
import { ACCESS_TOKEN_STORAGE_KEY } from "@/lib/api/api-client";

/**
 * 브라우저 로컬 세션 저장소.
 *
 * 액세스 토큰은 앱 웹뷰가 쓰던 것과 **같은 키**(`dodam.accessToken`)에 저장한다.
 * 그래야 기존 `api-client`와 커뮤니티 페이지가 그대로 인증된 호출을 한다.
 * 웹뷰와 달리 브라우저는 스스로 토큰을 재발급해야 하므로 리프레시 토큰과
 * 재발급/로그아웃에 필요한 deviceId도 함께 보관한다.
 */
const REFRESH_TOKEN_STORAGE_KEY = "dodam.refreshToken";
const DEVICE_ID_STORAGE_KEY = "dodam.deviceId";

function browserStorage(): Storage | null {
  if (typeof window === "undefined") return null;
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

export function readAccessToken(): string | null {
  return browserStorage()?.getItem(ACCESS_TOKEN_STORAGE_KEY) ?? null;
}

export function readRefreshToken(): string | null {
  return browserStorage()?.getItem(REFRESH_TOKEN_STORAGE_KEY) ?? null;
}

/** 로그인/재발급 성공 시 토큰을 저장한다. */
export function saveSession(session: AuthSession): void {
  const storage = browserStorage();
  if (storage == null) return;
  storage.setItem(ACCESS_TOKEN_STORAGE_KEY, session.accessToken);
  storage.setItem(REFRESH_TOKEN_STORAGE_KEY, session.refreshToken);
}

/** 로그아웃 시 토큰을 제거한다. deviceId는 기기 식별을 위해 유지한다. */
export function clearSession(): void {
  const storage = browserStorage();
  if (storage == null) return;
  storage.removeItem(ACCESS_TOKEN_STORAGE_KEY);
  storage.removeItem(REFRESH_TOKEN_STORAGE_KEY);
}

/**
 * 재발급·로그아웃 호출에 필요한 안정적인 기기 식별자를 얻는다.
 *
 * 백엔드는 `deviceId`를 필수로 요구한다. 최초 1회 UUID를 만들어 저장하고
 * 이후 재사용한다.
 */
export function getOrCreateDeviceId(): string {
  const storage = browserStorage();
  const existing = storage?.getItem(DEVICE_ID_STORAGE_KEY);
  if (existing != null && existing.length > 0) return existing;
  const generated = createUuid();
  storage?.setItem(DEVICE_ID_STORAGE_KEY, generated);
  return generated;
}

function createUuid(): string {
  const globalCrypto = globalThis.crypto;
  if (globalCrypto?.randomUUID) return globalCrypto.randomUUID();
  // randomUUID가 없는 환경(구형 브라우저) 대비 폴백.
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (char) => {
    const random = Math.floor(Math.random() * 16);
    const value = char === "x" ? random : (random & 0x3) | 0x8;
    return value.toString(16);
  });
}
