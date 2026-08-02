"use client";

import { useState } from "react";

import type { CommunityComment } from "@/features/community/domain/community-models";
import {
  useCommunityComments,
  useCreateCommunityComment,
  useDeleteCommunityComment,
  useUpdateCommunityComment,
} from "@/features/community/hooks/use-community";

const CONTENT_MAX = 2000;

function formatDate(value: string) {
  const parts = new Intl.DateTimeFormat("ko-KR", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(new Date(value));
  const part = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((item) => item.type === type)?.value ?? "";
  return `${part("year")}. ${part("month")}. ${part("day")} ${part("hour")}:${part("minute")}`;
}

export function CommunityCommentSection({
  postId,
  totalCount,
  onReport,
}: {
  postId: number;
  totalCount: number;
  onReport: (commentId: number) => void;
}) {
  const { data, isPending, isError, error, refetch } =
    useCommunityComments(postId);
  const createComment = useCreateCommunityComment(postId);
  const updateComment = useUpdateCommunityComment(postId);
  const deleteComment = useDeleteCommunityComment(postId);

  const [editingId, setEditingId] = useState<number | null>(null);
  const count = data?.length ?? totalCount;

  return (
    <section className="community-comments" aria-labelledby="comment-title">
      <h2 id="comment-title">댓글 {count}</h2>

      <CommentComposer
        pending={createComment.isPending}
        errorMessage={
          createComment.isError
            ? mutationMessage(createComment.error, "댓글을 등록하지 못했어요.")
            : undefined
        }
        onSubmit={(input) =>
          createComment.mutate(input, {
            onSuccess: () => createComment.reset(),
          })
        }
      />

      {isPending && (
        <div className="community-comments-empty">댓글을 불러오는 중이에요…</div>
      )}

      {isError && (
        <div className="community-comments-empty">
          <p>{mutationMessage(error, "댓글을 불러오지 못했어요.")}</p>
          <button
            type="button"
            className="community-button community-button-ghost"
            onClick={() => void refetch()}
          >
            다시 시도
          </button>
        </div>
      )}

      {data &&
        (data.length > 0 ? (
          <div className="community-comment-list">
            {data.map((comment) => (
              <CommentItem
                key={comment.id}
                comment={comment}
                isEditing={editingId === comment.id}
                isUpdating={updateComment.isPending}
                isDeleting={deleteComment.isPending}
                onStartEdit={() => setEditingId(comment.id)}
                onCancelEdit={() => setEditingId(null)}
                onSaveEdit={(content) =>
                  updateComment.mutate(
                    { commentId: comment.id, input: { content } },
                    { onSuccess: () => setEditingId(null) },
                  )
                }
                onDelete={() => {
                  if (!window.confirm("이 댓글을 삭제할까요?")) return;
                  deleteComment.mutate(comment.id);
                }}
                onReport={() => onReport(comment.id)}
              />
            ))}
          </div>
        ) : (
          <div className="community-comments-empty">
            아직 작성된 댓글이 없어요. 첫 댓글을 남겨보세요.
          </div>
        ))}
    </section>
  );
}

function CommentComposer({
  pending,
  errorMessage,
  onSubmit,
}: {
  pending: boolean;
  errorMessage?: string;
  onSubmit: (input: { content: string; anonymous: boolean }) => void;
}) {
  const [content, setContent] = useState("");
  const [anonymous, setAnonymous] = useState(false);

  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    const trimmed = content.trim();
    if (trimmed.length === 0 || pending) return;
    onSubmit({ content: trimmed, anonymous });
    setContent("");
    setAnonymous(false);
  };

  return (
    <form className="community-comment-composer" onSubmit={submit}>
      <textarea
        className="community-field-control community-field-textarea"
        rows={3}
        maxLength={CONTENT_MAX}
        placeholder="따뜻한 댓글을 남겨주세요"
        value={content}
        onChange={(event) => setContent(event.target.value)}
      />
      {errorMessage && (
        <p className="community-field-error" role="alert">
          {errorMessage}
        </p>
      )}
      <div className="community-comment-composer-actions">
        <label className="community-field-checkbox">
          <input
            type="checkbox"
            checked={anonymous}
            onChange={(event) => setAnonymous(event.target.checked)}
          />
          <span>익명</span>
        </label>
        <button
          type="submit"
          className="community-button community-button-primary"
          disabled={pending || content.trim().length === 0}
        >
          {pending ? "등록 중…" : "댓글 등록"}
        </button>
      </div>
    </form>
  );
}

function CommentItem({
  comment,
  isEditing,
  isUpdating,
  isDeleting,
  onStartEdit,
  onCancelEdit,
  onSaveEdit,
  onDelete,
  onReport,
}: {
  comment: CommunityComment;
  isEditing: boolean;
  isUpdating: boolean;
  isDeleting: boolean;
  onStartEdit: () => void;
  onCancelEdit: () => void;
  onSaveEdit: (content: string) => void;
  onDelete: () => void;
  onReport: () => void;
}) {
  const isExpert = comment.author.role === "EXPERT";
  const canManage = comment.editableByMe === true;
  const [draft, setDraft] = useState(comment.content);

  return (
    <article className="community-comment-card" data-expert={isExpert}>
      <header>
        <div className="community-comment-author">
          <span className="community-comment-avatar" aria-hidden="true">
            {comment.author.avatar}
          </span>
          <div>
            <div className="community-comment-name">
              <strong>
                {comment.anonymous ? "익명" : comment.author.nickname}
              </strong>
              {isExpert && <span>EXPERT ✓</span>}
              {comment.accepted && <span>채택</span>}
            </div>
            {comment.author.credential && <p>{comment.author.credential}</p>}
          </div>
        </div>
        <time dateTime={comment.createdAt}>{formatDate(comment.createdAt)}</time>
      </header>

      {isEditing ? (
        <div className="community-comment-edit">
          <textarea
            className="community-field-control community-field-textarea"
            rows={3}
            maxLength={CONTENT_MAX}
            value={draft}
            onChange={(event) => setDraft(event.target.value)}
          />
          <div className="community-comment-actions">
            <button
              type="button"
              className="community-button community-button-ghost"
              onClick={onCancelEdit}
              disabled={isUpdating}
            >
              취소
            </button>
            <button
              type="button"
              className="community-button community-button-primary"
              onClick={() => onSaveEdit(draft.trim())}
              disabled={isUpdating || draft.trim().length === 0}
            >
              {isUpdating ? "저장 중…" : "저장"}
            </button>
          </div>
        </div>
      ) : (
        <p className="community-comment-content">{comment.content}</p>
      )}

      {!isEditing && (
        <footer>
          {comment.helpfulCount > 0 && (
            <span>♥ 도움됐어요 {comment.helpfulCount}</span>
          )}
          {canManage && (
            <>
              <button
                type="button"
                className="community-comment-textbtn"
                onClick={onStartEdit}
                disabled={isDeleting}
              >
                수정
              </button>
              <button
                type="button"
                className="community-comment-textbtn"
                onClick={onDelete}
                disabled={isDeleting}
              >
                {isDeleting ? "삭제 중…" : "삭제"}
              </button>
            </>
          )}
          {!canManage && (
            <button
              type="button"
              className="community-comment-textbtn"
              onClick={onReport}
            >
              신고
            </button>
          )}
        </footer>
      )}
    </article>
  );
}

function mutationMessage(error: unknown, fallback: string): string {
  return error instanceof Error ? error.message : fallback;
}
