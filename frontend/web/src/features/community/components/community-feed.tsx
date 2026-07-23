import { CommunityPostCard } from "@/features/community/components/community-post-card";
import type { CommunityPost } from "@/features/community/domain/community-models";

export function CommunityFeed({ posts }: { posts: readonly CommunityPost[] }) {
  if (posts.length === 0) {
    return (
      <section className="community-empty-state" aria-labelledby="feed-title">
        <div className="community-empty-icon" aria-hidden="true">
          ✎
        </div>
        <h1 id="feed-title">아직 등록된 이야기가 없어요</h1>
        <p>다른 카테고리의 이야기를 살펴보세요.</p>
      </section>
    );
  }

  return (
    <section className="community-post-list" aria-label="커뮤니티 게시글">
      {posts.map((post) => (
        <CommunityPostCard key={post.id} post={post} />
      ))}
    </section>
  );
}
