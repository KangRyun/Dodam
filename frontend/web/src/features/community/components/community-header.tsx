"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Suspense, useSyncExternalStore, type FormEvent } from "react";

import { readAccessToken } from "@/features/auth/data/session-store";
import { CommunityAccountMenu } from "@/features/community/components/community-account-menu";

/** 다른 탭의 로그인/로그아웃(localStorage 변경)에도 헤더가 반응하도록 구독한다. */
function subscribeAuth(onChange: () => void): () => void {
  if (typeof window === "undefined") return () => {};
  window.addEventListener("storage", onChange);
  return () => window.removeEventListener("storage", onChange);
}

export function CommunityHeader() {
  return (
    <Suspense
      fallback={<CommunityHeaderContent currentQuery="" currentParams="" />}
    >
      <CommunityHeaderWithSearchParams />
    </Suspense>
  );
}

function CommunityHeaderWithSearchParams() {
  const searchParams = useSearchParams();
  return (
    <CommunityHeaderContent
      currentQuery={searchParams.get("query") ?? ""}
      currentParams={searchParams.toString()}
    />
  );
}

function CommunityHeaderContent({
  currentQuery,
  currentParams,
}: {
  currentQuery: string;
  currentParams: string;
}) {
  const router = useRouter();
  const pathname = usePathname();

  // 로그인 여부는 localStorage 액세스 토큰으로 판단한다(탭 간에도 유지된다).
  // 서버·첫 렌더에서는 알 수 없어 null 을 주고(자리표시), 클라이언트에서 확정한다
  // — 로그아웃 사용자에게 로그인 버튼이 잠깐 깜빡이며 노출되는 것을 막는다.
  const isAuthed = useSyncExternalStore<boolean | null>(
    subscribeAuth,
    () => readAccessToken() != null,
    () => null,
  );

  const handleSearch = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const next =
      pathname === "/community"
        ? new URLSearchParams(currentParams)
        : new URLSearchParams();
    const formData = new FormData(event.currentTarget);
    const normalized = String(formData.get("query") ?? "").trim();
    if (normalized) next.set("query", normalized);
    else next.delete("query");
    router.push(`/community${next.size > 0 ? `?${next}` : ""}`);
  };

  return (
    <header className="community-header">
      <div className="community-header-inner">
        <a
          className="community-brand"
          href="/community"
          aria-label="도담 커뮤니티 홈"
        >
          <span aria-hidden="true">🖍️</span>
          <span>도담 커뮤니티</span>
        </a>

        <form className="community-search" role="search" onSubmit={handleSearch}>
          <span className="sr-only">커뮤니티 검색</span>
          <span aria-hidden="true">⌕</span>
          <input
            type="search"
            placeholder="관심 있는 이야기를 검색해보세요"
            aria-label="관심 있는 이야기 검색"
            name="query"
            defaultValue={currentQuery}
            maxLength={100}
          />
          <button type="submit">검색</button>
        </form>

        {isAuthed === null ? (
          // 마운트 전에는 자리만 잡아 레이아웃이 흔들리지 않게 한다.
          <span className="community-auth-slot" aria-hidden="true" />
        ) : isAuthed ? (
          <CommunityAccountMenu />
        ) : (
          <a className="community-login-button" href="/login">
            로그인 · 회원가입
          </a>
        )}
      </div>
    </header>
  );
}
