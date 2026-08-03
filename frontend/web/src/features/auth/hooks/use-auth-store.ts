"use client";

import { create } from "zustand";

import type { AuthUser } from "@/features/auth/domain/auth-models";

/**
 * 로그인/온보딩 흐름에서 쓰는 최소 인증 상태.
 *
 * 액세스·리프레시 토큰은 `session-store`(localStorage)가 관리한다. 여기서는
 * 온보딩 화면이 조건부 이메일 등을 판단하는 데 필요한 `user`만 보관하고,
 * 새로고침에도 살아남도록 sessionStorage에 미러링한다.
 */
const USER_STORAGE_KEY = "dodam.authUser";

type AuthState = {
  user: AuthUser | null;
  setUser: (user: AuthUser | null) => void;
  /** 새로고침 후 sessionStorage에서 user를 복원한다. */
  hydrate: () => void;
};

export const useAuthStore = create<AuthState>((set) => ({
  user: null,
  setUser: (user) => {
    set({ user });
    try {
      if (user) {
        window.sessionStorage.setItem(USER_STORAGE_KEY, JSON.stringify(user));
      } else {
        window.sessionStorage.removeItem(USER_STORAGE_KEY);
      }
    } catch {
      // sessionStorage 접근 불가 환경은 무시한다(메모리 상태만 사용).
    }
  },
  hydrate: () => {
    try {
      const raw = window.sessionStorage.getItem(USER_STORAGE_KEY);
      if (raw != null) set({ user: JSON.parse(raw) as AuthUser });
    } catch {
      // 무시.
    }
  },
}));
