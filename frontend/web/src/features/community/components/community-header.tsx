"use client";

import type { FormEvent } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";

export function CommunityHeader() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const currentQuery = searchParams.get("query") ?? "";

  const handleSearch = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const next = pathname === "/community"
      ? new URLSearchParams(searchParams.toString())
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
        <a className="community-brand" href="/community" aria-label="마음그림 커뮤니티 홈">
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
