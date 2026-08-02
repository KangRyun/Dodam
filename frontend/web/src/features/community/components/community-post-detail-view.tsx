"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";

import { CommunityCommentSection } from "@/features/community/components/community-comment-section";
import { CommunityHeader } from "@/features/community/components/community-header";
import { CommunityPostDetail } from "@/features/community/components/community-post-detail";
import {
  CommunityReportDialog,
  type CommunityReportTarget,
} from "@/features/community/components/community-report-dialog";
import {
  useCommunityPost,
  useDeleteCommunityPost,
  useToggleCommunityPostLike,
} from "@/features/community/hooks/use-community";

export function CommunityPostDetailView({ postId }: { postId: number }) {
  const router = useRouter();
  const [reportTarget, setReportTarget] =
    useState<CommunityReportTarget | null>(null);
  const { data, isPending, isError, error, refetch } =
    useCommunityPost(postId);
  const deletePost = useDeleteCommunityPost(postId);
  const toggleLike = useToggleCommunityPostLike(postId);

  const handleDelete = () => {
    if (deletePost.isPending) return;
    const confirmed = window.confirm("이 게시글을 삭제할까요?");
    if (!confirmed) return;
    deletePost.mutate(undefined, {
      onSuccess: () => router.push("/community"),
      onError: (mutationError) => {
        window.alert(
          mutationError instanceof Error
            ? mutationError.message
            : "게시글을 삭제하지 못했어요.",
        );
      },
    });
  };

  return (
    <div className="community-page">
      <CommunityHeader />

      {isPending && (
        <CommunityDetailStatus message="게시글을 불러오는 중이에요…" />
      )}

      {isError && (
        <CommunityDetailStatus
          message={
            error instanceof Error
              ? error.message
              : "게시글을 불러오지 못했어요."
          }
          onRetry={() => void refetch()}
        />
      )}

      {data === null && (
        <CommunityDetailStatus message="게시글을 찾을 수 없어요." showHome />
      )}

      {data && (
        <CommunityPostDetail
          post={data}
          onEdit={() => router.push(`/community/posts/${postId}/edit`)}
          onDelete={handleDelete}
          isDeleting={deletePost.isPending}
          onToggleLike={() => {
            if (toggleLike.isPending) return;
            toggleLike.mutate({ liked: data.isLiked });
          }}
          isLikePending={toggleLike.isPending}
          likeError={
            toggleLike.isError
              ? toggleLike.error.message || "좋아요를 처리하지 못했어요."
              : null
          }
          onReport={
            data.editableByMe
              ? undefined
              : () => setReportTarget({ type: "POST", id: postId })
          }
          commentsSlot={
            <CommunityCommentSection
              postId={postId}
              totalCount={data.commentCount}
              onReport={(commentId) =>
                setReportTarget({ type: "COMMENT", id: commentId })
              }
            />
          }
        />
      )}

      {reportTarget && (
        <CommunityReportDialog
          target={reportTarget}
          onClose={() => setReportTarget(null)}
        />
      )}
    </div>
  );
}

function CommunityDetailStatus({
  message,
  onRetry,
  showHome = false,
}: {
  message: string;
  onRetry?: () => void;
  showHome?: boolean;
}) {
  return (
    <main className="community-detail-main">
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
        {showHome && (
          <Link className="community-button community-button-ghost" href="/community">
            커뮤니티로 돌아가기
          </Link>
        )}
      </section>
    </main>
  );
}
