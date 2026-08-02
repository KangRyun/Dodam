"use client";

import Link from "next/link";
import type { ReactNode } from "react";

import { categoryLabels } from "@/features/community/community-category";
import type { CommunityPost } from "@/features/community/domain/community-models";

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

type CommunityPostDetailProps = {
  post: CommunityPost;
  /** 작성자 본인일 때 수정 화면으로 이동시키는 콜백. */
  onEdit?: () => void;
  /** 작성자 본인/관리자일 때 게시글을 삭제하는 콜백. */
  onDelete?: () => void;
  /** 삭제 요청이 진행 중인지. */
  isDeleting?: boolean;
  /** 좋아요 등록·취소 콜백. */
  onToggleLike?: () => void;
  /** 좋아요 요청 진행 여부. */
  isLikePending?: boolean;
  /** 좋아요 처리 실패 안내. */
  likeError?: string | null;
  /** 게시글 신고 창을 여는 콜백. */
  onReport?: () => void;
  /** 댓글 영역. 별도 조회(COMM-16) 기반 섹션을 주입한다. */
  commentsSlot?: ReactNode;
};

export function CommunityPostDetail({
  post,
  onEdit,
  onDelete,
  isDeleting = false,
  onToggleLike,
  isLikePending = false,
  likeError,
  onReport,
  commentsSlot,
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
            {onReport && (
              <button type="button" aria-label="게시글 신고" onClick={onReport}>
                신고
              </button>
            )}
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
            <button
              type="button"
              className="community-like-button"
              data-liked={post.isLiked}
              aria-pressed={post.isLiked}
              aria-label={post.isLiked ? "좋아요 취소" : "좋아요"}
              onClick={onToggleLike}
              disabled={isLikePending || onToggleLike === undefined}
            >
              <span aria-hidden="true">{post.isLiked ? "♥" : "♡"}</span>
              <span>{post.likeCount}</span>
            </button>
            <span>💬 {post.commentCount}</span>
          </div>
          <button type="button">스크랩</button>
        </footer>
        {likeError && (
          <p className="community-like-error" role="alert">
            {likeError}
          </p>
        )}
      </article>

      {commentsSlot}
    </main>
  );
}
