"use client";

import Link from "next/link";

import { CommunityCategoryTabs } from "@/features/community/components/community-category-tabs";
import { CommunityFeed } from "@/features/community/components/community-feed";
import { CommunityShell } from "@/features/community/components/community-shell";
import { CommunitySidebarContent } from "@/features/community/components/community-sidebar-content";
import { useCommunityFeed } from "@/features/community/hooks/use-community";
import type { CommunityPostCategory } from "@/features/community/domain/community-models";

export function CommunityFeedView({
  category,
}: {
  category?: CommunityPostCategory;
}) {
  const { data, isPending, isError, error, refetch } = useCommunityFeed({
    category,
  });

  return (
    <CommunityShell
      navigation={<CommunityCategoryTabs selectedCategory={category} />}
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
        <Link
          className="community-button community-button-primary"
          href="/community/write"
        >
          ✎ 글쓰기
        </Link>
      </div>

      {isPending && <CommunityFeedStatus message="이야기를 불러오는 중이에요…" />}

      {isError && (
        <CommunityFeedStatus
          message={
            error instanceof Error
              ? error.message
              : "이야기를 불러오지 못했어요."
          }
          onRetry={() => void refetch()}
        />
      )}

      {data && <CommunityFeed posts={data.posts} />}
    </CommunityShell>
  );
}

function CommunityFeedStatus({
  message,
  onRetry,
}: {
  message: string;
  onRetry?: () => void;
}) {
  return (
    <section className="community-feed-status" aria-live="polite">
      <p>{message}</p>
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
