"use client";

import Link from "next/link";

import { CommunityFeed } from "@/features/community/components/community-feed";
import { CommunityShell } from "@/features/community/components/community-shell";
import { CommunitySidebarContent } from "@/features/community/components/community-sidebar-content";
import { useCommunityPersonalPosts } from "@/features/community/hooks/use-community";

export function CommunityPersonalFeedView({
  mode,
}: {
  mode: "mine" | "liked";
}) {
  const query = useCommunityPersonalPosts(mode);
  const title = mode === "mine" ? "내가 쓴 글" : "좋아요 한 글";

  return (
    <CommunityShell
      navigation={
        <div className="community-personal-heading">
          <Link href="/community" aria-label="커뮤니티로 돌아가기">←</Link>
          <h1>{title}</h1>
        </div>
      }
      sidebar={
        query.data ? (
          <CommunitySidebarContent
            profile={query.data.profile}
            popularTags={query.data.popularTags}
          />
        ) : null
      }
    >
      {query.isPending && <PersonalStatus message="게시글을 불러오는 중이에요…" />}
      {query.isError && (
        <PersonalStatus
          message="게시글을 불러오지 못했어요."
          onRetry={() => void query.refetch()}
        />
      )}
      {query.data && query.data.posts.length === 0 ? (
        <section className="community-empty-state">
          <div className="community-empty-icon" aria-hidden="true">
            {mode === "mine" ? "✎" : "♥"}
          </div>
          <h1>{mode === "mine" ? "아직 작성한 글이 없어요" : "아직 좋아요한 글이 없어요"}</h1>
          <p>{mode === "mine" ? "첫 이야기를 커뮤니티에 남겨 보세요." : "마음에 드는 이야기에 좋아요를 눌러 보세요."}</p>
        </section>
      ) : query.data ? (
        <CommunityFeed posts={query.data.posts} />
      ) : null}
    </CommunityShell>
  );
}

function PersonalStatus({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <section className="community-feed-status" aria-live="polite">
      <p>{message}</p>
      {onRetry && <button type="button" className="community-button community-button-ghost" onClick={onRetry}>다시 시도</button>}
    </section>
  );
}
