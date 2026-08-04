import Link from "next/link";

import {
  categoryIcons,
  categoryLabels,
} from "@/features/community/community-category";
import type { CommunityPost } from "@/features/community/domain/community-models";

function formatPostDate(value: string) {
  const date = new Date(value);
  const now = new Date();
  const elapsed = now.getTime() - date.getTime();
  const hours = Math.floor(elapsed / (1000 * 60 * 60));
  const days = Math.floor(hours / 24);

  if (hours >= 0 && hours < 24) return `${Math.max(hours, 1)}시간 전`;
  if (days === 1) return "어제";
  if (days > 1 && days < 7) return `${days}일 전`;
  return `${date.getMonth() + 1}/${date.getDate()}`;
}

export function CommunityPostCard({ post }: { post: CommunityPost }) {
  const thumbnailIcon = categoryIcons[post.category];

  return (
    <Link className="community-post-link" href={`/community/posts/${post.id}`}>
      <article className="community-post-card" data-category={post.category}>
        <div className="community-post-copy">
          <div className="community-post-badges">
            <span
              className="community-post-category"
              data-category={post.category}
            >
              {categoryLabels[post.category]}
            </span>
            {post.answerStatus === "ANSWERED" && (
              <span className="community-answer-status">답변 완료</span>
            )}
          </div>

          <h2>{post.title}</h2>
          <p className="community-post-excerpt">{post.excerpt}</p>

          <div className="community-post-meta">
            <span>{post.isAnonymous ? "익명" : post.author.nickname}</span>
            <span aria-hidden="true">·</span>
            <span>댓글 {post.commentCount}</span>
            <span aria-hidden="true">·</span>
            <time dateTime={post.createdAt}>{formatPostDate(post.createdAt)}</time>
          </div>
        </div>

        {post.imageUrl && (
          <div className="community-post-thumbnail" aria-label="게시글 첨부 이미지">
            <span aria-hidden="true">{thumbnailIcon ?? "🖼️"}</span>
          </div>
        )}
      </article>
    </Link>
  );
}
