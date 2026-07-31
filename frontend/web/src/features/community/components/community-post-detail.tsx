"use client";

import Link from "next/link";

import { categoryLabels } from "@/features/community/community-category";
import type {
  CommunityComment,
  CommunityPost,
} from "@/features/community/domain/community-models";

function formatDate(value: string) {
  const date = new Date(value);
  const parts = new Intl.DateTimeFormat("ko-KR", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(date);
  const part = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((item) => item.type === type)?.value ?? "";

  return `${part("year")}. ${part("month")}. ${part("day")} ${part("hour")}:${part("minute")}`;
}

function CommunityCommentCard({ comment }: { comment: CommunityComment }) {
  const isExpert = comment.author.role === "EXPERT";

  return (
    <article className="community-comment-card" data-expert={isExpert}>
      <header>
        <div className="community-comment-author">
          <span className="community-comment-avatar" aria-hidden="true">
            {comment.author.avatar}
          </span>
          <div>
            <div className="community-comment-name">
              <strong>{comment.author.nickname}</strong>
              {isExpert && <span>EXPERT ✓</span>}
            </div>
            {comment.author.credential && <p>{comment.author.credential}</p>}
          </div>
        </div>
        <time dateTime={comment.createdAt}>{formatDate(comment.createdAt)}</time>
      </header>
      <p className="community-comment-content">{comment.content}</p>
      <footer>
        {comment.helpfulCount > 0 && <span>♥ 도움됐어요 {comment.helpfulCount}</span>}
        <span>답글</span>
      </footer>
    </article>
  );
}

type CommunityPostDetailProps = {
  post: CommunityPost;
  /** 작성자 본인일 때 수정 화면으로 이동시키는 콜백. */
  onEdit?: () => void;
  /** 작성자 본인/관리자일 때 게시글을 삭제하는 콜백. */
  onDelete?: () => void;
  /** 삭제 요청이 진행 중인지. */
  isDeleting?: boolean;
};

export function CommunityPostDetail({
  post,
  onEdit,
  onDelete,
  isDeleting = false,
}: CommunityPostDetailProps) {
  const canManage = post.editableByMe === true;

  return (
    <main className="community-detail-main">
      <Link className="community-detail-back" href="/community">
        ‹ {categoryLabels[post.category]}
      </Link>

      <article className="community-detail-card">
        <div className="community-detail-badges">
          <span>{categoryLabels[post.category]}</span>
          {post.answerStatus === "ANSWERED" && <span>답변 완료</span>}
        </div>

        <div className="community-detail-title-row">
          <h1>{post.title}</h1>
          <div className="community-detail-actions">
            {canManage && onEdit && (
              <button
                type="button"
                onClick={onEdit}
                disabled={isDeleting}
              >
                수정
              </button>
            )}
            {canManage && onDelete && (
              <button
                type="button"
                onClick={onDelete}
                disabled={isDeleting}
              >
                {isDeleting ? "삭제 중…" : "삭제"}
              </button>
            )}
            <button type="button" aria-label="게시글 신고">
              신고
            </button>
          </div>
        </div>

        <div className="community-detail-author">
          <span aria-hidden="true">{post.author.avatar}</span>
          <div>
            <strong>{post.isAnonymous ? "익명" : post.author.nickname}</strong>
            <p>
              <time dateTime={post.createdAt}>{formatDate(post.createdAt)}</time>
              <span>·</span>
              <span>조회 {post.viewCount}</span>
            </p>
          </div>
        </div>

        <div className="community-detail-content">
          {post.content.split("\n").map((paragraph, index) =>
            paragraph.length === 0 ? (
              <br key={`space-${index}`} />
            ) : (
              <p key={`paragraph-${index}`}>{paragraph}</p>
            ),
          )}
        </div>

        {post.imageUrl && (
          <div className="community-detail-image" aria-label="게시글 첨부 이미지">
            <span>아이 그림 · 첨부 이미지</span>
          </div>
        )}

        <footer className="community-detail-reactions">
          <div>
            <span>♥ {post.likeCount}</span>
            <span>💬 {post.commentCount}</span>
          </div>
          <button type="button">스크랩</button>
        </footer>
      </article>

      <section className="community-comments" aria-labelledby="comment-title">
        <h2 id="comment-title">댓글 {post.commentCount}</h2>
        {post.comments.length > 0 ? (
          <div className="community-comment-list">
            {post.comments.map((comment) => (
              <CommunityCommentCard key={comment.id} comment={comment} />
            ))}
          </div>
        ) : (
          <div className="community-comments-empty">
            아직 작성된 댓글이 없어요.
          </div>
        )}
      </section>
    </main>
  );
}
