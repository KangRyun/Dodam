"use client";

import { useEffect } from "react";

import { authRepository } from "@/features/auth/data/auth-repository-factory";
import type { AuthUser } from "@/features/auth/domain/auth-models";
import { useAuthStore } from "@/features/auth/hooks/use-auth-store";

/** 로그인 사용자가 없을 때 사이드바·프로필에 보여줄 기본 이름. */
export const GUEST_NICKNAME = "게스트";

/**
 * 커뮤니티 화면이 쓰는 "현재 로그인 사용자".
 *
 * 이름의 진짜 출처는 zustand 인증 스토어(`useAuthStore`)다. 새로고침 등으로 메모리
 * 상태가 비면 sessionStorage에서 복원하고, 그래도 없으면 `GET /users/me`로 조회해
 * 채운다. 비로그인 상태면 `nickname`은 게스트로 둔다.
 */
export function useCommunityViewer(): {
  user: AuthUser | null;
  nickname: string;
} {
  const user = useAuthStore((state) => state.user);

  useEffect(() => {
    if (useAuthStore.getState().user != null) return;
    // 1) sessionStorage 복원 시도.
    useAuthStore.getState().hydrate();
    if (useAuthStore.getState().user != null) return;
    // 2) 그래도 없으면 서버에서 조회한다(토큰이 없으면 조용히 실패 → 게스트).
    let active = true;
    void authRepository
      .getMe()
      .then((me) => {
        if (active) useAuthStore.getState().setUser(me);
      })
      .catch(() => {
        // 비로그인 상태이므로 게스트로 둔다.
      });
    return () => {
      active = false;
    };
  }, []);

  return { user, nickname: user?.nickname ?? GUEST_NICKNAME };
}
