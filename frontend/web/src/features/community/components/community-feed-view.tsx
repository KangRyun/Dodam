"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";

import { CommunityCategoryTabs } from "@/features/community/components/community-category-tabs";
import { CommunityFeed } from "@/features/community/components/community-feed";
import { CommunityHero } from "@/features/community/components/community-hero";
import { CommunityShell } from "@/features/community/components/community-shell";
import { CommunitySidebarContent } from "@/features/community/components/community-sidebar-content";
import { useCommunityFeed } from "@/features/community/hooks/use-community";
import type {
  CommunityPostCategory,
  CommunityPostSort,
} from "@/features/community/domain/community-models";
import { ApiClientError } from "@/lib/api/api-client";

/** 인증 만료(401) 여부. 재발급까지 실패해 로그인이 필요한 상태다. */
function isAuthError(error: unknown): boolean {
  return error instanceof ApiClientError && error.status === 401;
}

export function CommunityFeedView({
  category,
  query,
  sort = "createdAt,desc",
}: {
  category?: CommunityPostCategory;
  query?: string;
  sort?: CommunityPostSort;
}) {
  const router = useRouter();
  const { data, isPending, isError, error, refetch } = useCommunityFeed({
    category,
    query,
    sort,
  });

  const handleSort = (nextSort: CommunityPostSort) => {
    const params = new URLSearchParams();
    if (category) params.set("category", category);
    if (query) params.set("query", query);
    if (nextSort !== "createdAt,desc") params.set("sort", nextSort);
    router.push(`/community${params.size > 0 ? `?${params}` : ""}`, {
      scroll: false,
    });
  };

  return (
    <CommunityShell
      hero={<CommunityHero />}
      navigation={
        <CommunityCategoryTabs
          selectedCategory={category}
          query={query}
          sort={sort === "createdAt,desc" ? undefined : sort}
        />
      }
      sidebar={
        data ? (
          <CommunitySidebarContent
            profile={data.profile}
            popularTags={data.popularTags}
          />
        ) : null
      }
    >
      <div className="community-feed-toolbar">
        <label className="community-sort-control">
          <span>정렬</span>
          <select
            value={sort}
            aria-label="게시글 정렬"
            onChange={(event) =>
              handleSort(event.target.value as CommunityPostSort)
            }
          >
            <option value="createdAt,desc">최신순</option>
            <option value="createdAt,asc">오래된순</option>
            <option value="likeCount,desc">좋아요순</option>
          </select>
        </label>
        <Link
          className="community-button community-button-primary"
          href="/community/write"
        >
          ✎ 글쓰기
        </Link>
      </div>

      {isPending && <CommunityFeedStatus message="이야기를 불러오는 중이에요…" />}

      {isError &&
        (isAuthError(error) ? (
          <CommunityFeedStatus
            message="로그인이 필요해요. 다시 로그인해 주세요."
            actionHref="/login"
            actionLabel="로그인 하기"
          />
        ) : (
          <CommunityFeedStatus
            message="이야기를 불러오지 못했어요. 잠시 후 다시 시도해 주세요."
            onRetry={() => void refetch()}
          />
        ))}

      {data && <CommunityFeed posts={data.posts} />}
    </CommunityShell>
  );
}

function CommunityFeedStatus({
  message,
  onRetry,
  actionHref,
  actionLabel,
}: {
  message: string;
  onRetry?: () => void;
  actionHref?: string;
  actionLabel?: string;
}) {
  return (
    <section className="community-feed-status" aria-live="polite">
      <p>{message}</p>
      {actionHref && actionLabel && (
        <Link
          className="community-button community-button-primary"
          href={actionHref}
        >
          {actionLabel}
        </Link>
      )}
      {onRetry && (
        <button
          type="button"
          className="community-button community-button-ghost"
          onClick={onRetry}
        >
          다시 시도
        </button>
      )}
    </section>
  );
}
