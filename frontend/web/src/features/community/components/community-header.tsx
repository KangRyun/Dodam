"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Suspense, type FormEvent } from "react";

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
          aria-label="마음그림 커뮤니티 홈"
        >
          <span aria-hidden="true">🖍️</span>
          <span>마음그림 커뮤니티</span>
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

        <button
          className="community-profile-button"
          type="button"
          aria-label="내 커뮤니티 메뉴"
        >
          🌱
        </button>
      </div>
    </header>
  );
}
