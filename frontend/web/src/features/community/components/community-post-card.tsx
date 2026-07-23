import type {
  CommunityPost,
  CommunityPostCategory,
} from "@/features/community/domain/community-models";

const categoryLabels: Record<CommunityPostCategory, string> = {
  GUARDIAN_STORY: "보호자 이야기",
  ACTIVITY_REVIEW: "활동 후기",
  EXPERT_COLUMN: "칼럼",
  ART_ACTIVITY_RESOURCE: "미술 활동 자료",
  DRAWING_GUIDE: "그림 활동 가이드",
  EXPERT_QNA: "전문가 Q&A",
  NOTICE: "공지",
};

const categoryIcons: Partial<Record<CommunityPostCategory, string>> = {
  GUARDIAN_STORY: "🌧️",
  ACTIVITY_REVIEW: "🖼️",
  EXPERT_COLUMN: "🖍️",
  ART_ACTIVITY_RESOURCE: "🎨",
  DRAWING_GUIDE: "📒",
};

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
    <article className="community-post-card">
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
  );
}
