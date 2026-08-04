"use client";

import { useEffect, useRef, useState } from "react";

import { authRepository } from "@/features/auth/data/auth-repository-factory";
import {
  clearSession,
  getOrCreateDeviceId,
  readRefreshToken,
} from "@/features/auth/data/session-store";
import { useAuthStore } from "@/features/auth/hooks/use-auth-store";

/**
 * 로그인 상태의 계정 메뉴.
 *
 * 프로필 버튼을 누르면 계정 관련 페이지 진입점과 로그아웃을 담은 드롭다운을 연다.
 * (기존에는 진입점이 없어 my-posts·liked-posts·settings 로 갈 방법이 없었고,
 *  로그아웃 UI 자체도 없었다 — S15P11B209-817.)
 */
const MENU_LINKS = [
  { href: "/community/profile", label: "내 프로필" },
  { href: "/community/my-posts", label: "내 글" },
  { href: "/community/liked-posts", label: "좋아요한 글" },
  { href: "/community/settings", label: "설정" },
] as const;

export function CommunityAccountMenu() {
  const [open, setOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  // 바깥 클릭·Esc 로 닫는다. 열려 있을 때만 리스너를 단다.
  useEffect(() => {
    if (!open) return;
    const handlePointerDown = (event: PointerEvent) => {
      if (!containerRef.current?.contains(event.target as Node)) setOpen(false);
    };
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
    };
    document.addEventListener("pointerdown", handlePointerDown);
    document.addEventListener("keydown", handleKeyDown);
    return () => {
      document.removeEventListener("pointerdown", handlePointerDown);
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, [open]);

  const handleLogout = async () => {
    setOpen(false);
    const refreshToken = readRefreshToken();
    const deviceId = getOrCreateDeviceId();
    try {
      if (refreshToken) {
        await authRepository.logout({ refreshToken, deviceId });
      }
    } catch {
      // 서버 로그아웃 호출이 실패해도 로컬 세션은 반드시 정리한다.
    }
    clearSession();
    useAuthStore.getState().setUser(null);
    // 전체 리로드로 헤더의 로그인 상태를 확실히 리셋한다(같은 탭에서는
    // localStorage 변경 이벤트가 발생하지 않아 자동 갱신되지 않는다).
    window.location.assign("/community");
  };

  return (
    <div className="community-account" ref={containerRef}>
      <button
        type="button"
        className="community-profile-button"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label="내 커뮤니티 메뉴"
        onClick={() => setOpen((value) => !value)}
      >
        🌱
      </button>

      {open ? (
        <div className="community-account-menu" role="menu">
          {MENU_LINKS.map((item) => (
            <a
              key={item.href}
              role="menuitem"
              className="community-account-menu-item"
              href={item.href}
            >
              {item.label}
            </a>
          ))}
          <button
            type="button"
            role="menuitem"
            className="community-account-menu-item community-account-logout"
            onClick={handleLogout}
          >
            로그아웃
          </button>
        </div>
      ) : null}
    </div>
  );
}
