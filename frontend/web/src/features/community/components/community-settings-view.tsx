"use client";

import Link from "next/link";
import { useState, useSyncExternalStore } from "react";

import { CommunityShell } from "@/features/community/components/community-shell";
import {
  readCompactFeedPreference,
  subscribeCommunityPreference,
  writeCompactFeedPreference,
} from "@/features/community/community-preferences";
import { authRepository } from "@/features/auth/data/auth-repository-factory";
import {
  clearSession,
  getOrCreateDeviceId,
  readAuthProvider,
  readRefreshToken,
} from "@/features/auth/data/session-store";
import type { AuthProviderId } from "@/features/auth/domain/auth-models";
import { useAuthStore } from "@/features/auth/hooks/use-auth-store";

const PROVIDER_LABELS: Record<AuthProviderId, string> = {
  kakao: "카카오",
  google: "구글",
  naver: "네이버",
};

export function CommunitySettingsView() {
  const compactFeed = useSyncExternalStore(
    subscribeCommunityPreference,
    readCompactFeedPreference,
    () => false,
  );

  // localStorage 값은 클라이언트에서만 읽어 하이드레이션 불일치를 피한다.
  // 세션 중에는 바뀌지 않으므로 구독은 비워 둔다.
  const provider = useSyncExternalStore(
    () => () => {},
    () => readAuthProvider(),
    () => null,
  );
  const [confirmingWithdraw, setConfirmingWithdraw] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const updateCompactFeed = (checked: boolean) => {
    writeCompactFeedPreference(checked);
  };

  const handleLogout = async () => {
    if (busy) return;
    setBusy(true);
    const refreshToken = readRefreshToken();
    const deviceId = getOrCreateDeviceId();
    try {
      if (refreshToken) {
        await authRepository.logout({ refreshToken, deviceId });
      }
    } catch {
      // 서버 로그아웃이 실패해도 로컬 세션은 반드시 정리한다.
    }
    clearSession();
    useAuthStore.getState().setUser(null);
    // 전체 리로드로 헤더의 로그인 상태를 확실히 리셋한다.
    window.location.assign("/community");
  };

  const handleWithdraw = async () => {
    if (busy) return;
    setBusy(true);
    setError(null);
    const refreshToken = readRefreshToken();
    const deviceId = getOrCreateDeviceId();
    try {
      await authRepository.deleteAccount({
        refreshToken: refreshToken ?? "",
        deviceId,
      });
    } catch (caught) {
      setError(
        caught instanceof Error
          ? caught.message
          : "회원 탈퇴를 처리하지 못했어요. 잠시 후 다시 시도해 주세요.",
      );
      setBusy(false);
      return;
    }
    clearSession();
    useAuthStore.getState().setUser(null);
    // 탈퇴 후에는 랜딩 화면으로 이동한다.
    window.location.assign("/");
  };

  return (
    <CommunityShell
      sidebar={null}
      navigation={
        <div className="community-personal-heading">
          <Link href="/community" aria-label="커뮤니티로 돌아가기">←</Link>
          <h1>커뮤니티 설정</h1>
        </div>
      }
    >
      <section className="community-settings-card">
        <div>
          <h2>목록을 간단히 보기</h2>
          <p>게시글 목록에서 핵심 내용 위주로 표시해요.</p>
        </div>
        <label className="community-switch">
          <input
            type="checkbox"
            checked={compactFeed}
            onChange={(event) => updateCompactFeed(event.target.checked)}
          />
          <span aria-hidden="true" />
        </label>
      </section>

      <section className="community-settings-card community-settings-guide">
        <div>
          <h2>알림 설정</h2>
          <p>댓글과 서비스 알림은 도담 앱의 설정에서 관리할 수 있어요.</p>
        </div>
      </section>

      <section className="community-settings-card community-settings-guide">
        <div>
          <h2>계정 연결</h2>
          <p>
            {provider
              ? `${PROVIDER_LABELS[provider]} 계정으로 연결됨`
              : "연결 정보 없음"}
          </p>
        </div>
      </section>

      <section className="community-settings-card community-settings-guide">
        <div>
          <h2>로그아웃</h2>
          <p>이 브라우저에서 로그아웃해요. 다시 로그인하면 이어서 이용할 수 있어요.</p>
        </div>
        <button
          type="button"
          className="community-button community-button-ghost"
          onClick={() => void handleLogout()}
          disabled={busy}
          aria-label="로그아웃"
        >
          로그아웃
        </button>
      </section>

      <section className="community-settings-card community-settings-danger">
        <div>
          <h2>회원 탈퇴</h2>
          <p>
            탈퇴하면 계정과 로그인 정보가 삭제돼요. 다만 커뮤니티에 남긴 글과 댓글은
            삭제되지 않고 그대로 남아요.
          </p>
          {error ? (
            <p className="community-settings-error" role="alert">
              {error}
            </p>
          ) : null}
          {confirmingWithdraw ? (
            <div className="community-settings-confirm">
              <p>정말 탈퇴할까요? 이 작업은 되돌릴 수 없어요.</p>
              <div className="community-settings-confirm-actions">
                <button
                  type="button"
                  className="community-button community-button-ghost"
                  onClick={() => setConfirmingWithdraw(false)}
                  disabled={busy}
                  aria-label="회원 탈퇴 취소"
                >
                  취소
                </button>
                <button
                  type="button"
                  className="community-button community-button-danger"
                  onClick={() => void handleWithdraw()}
                  disabled={busy}
                  aria-label="회원 탈퇴 확정"
                >
                  {busy ? "처리 중…" : "탈퇴하기"}
                </button>
              </div>
            </div>
          ) : null}
        </div>
        {confirmingWithdraw ? null : (
          <button
            type="button"
            className="community-button community-button-danger"
            onClick={() => {
              setError(null);
              setConfirmingWithdraw(true);
            }}
            disabled={busy}
            aria-label="회원 탈퇴"
          >
            회원 탈퇴
          </button>
        )}
      </section>
    </CommunityShell>
  );
}
