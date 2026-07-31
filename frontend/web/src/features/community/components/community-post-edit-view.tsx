"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";

import { CommunityHeader } from "@/features/community/components/community-header";
import { CommunityPostForm } from "@/features/community/components/community-post-form";
import {
  useCommunityPost,
  useUpdateCommunityPost,
} from "@/features/community/hooks/use-community";

export function CommunityPostEditView({ postId }: { postId: number }) {
  const router = useRouter();
  const { data, isPending, isError, error } = useCommunityPost(postId);
  const updatePost = useUpdateCommunityPost(postId);

  const backToPost = `/community/posts/${postId}`;

  return (
    <div className="community-page">
      <CommunityHeader />
      <main className="community-detail-main">
        {isPending && (
          <section className="community-feed-status" aria-live="polite">
            <p>게시글을 불러오는 중이에요…</p>
          </section>
        )}

        {isError && (
          <section className="community-feed-status" aria-live="polite">
            <p>
              {error instanceof Error
                ? error.message
                : "게시글을 불러오지 못했어요."}
            </p>
            <Link
              className="community-button community-button-ghost"
              href={backToPost}
            >
              돌아가기
            </Link>
          </section>
        )}

        {data === null && (
          <section className="community-feed-status" aria-live="polite">
            <p>게시글을 찾을 수 없어요.</p>
            <Link
              className="community-button community-button-ghost"
              href="/community"
            >
              커뮤니티로 돌아가기
            </Link>
          </section>
        )}

        {data && (
          <CommunityPostForm
            heading="글 수정"
            submitLabel="수정 완료"
            defaultValues={{
              postType: data.category,
              title: data.title,
              content: data.content,
              anonymous: data.isAnonymous,
            }}
            pending={updatePost.isPending}
            errorMessage={
              updatePost.isError
                ? updatePost.error instanceof Error
                  ? updatePost.error.message
                  : "게시글을 수정하지 못했어요."
                : undefined
            }
            onSubmit={(input) =>
              updatePost.mutate(input, {
                onSuccess: () => router.push(backToPost),
              })
            }
          />
        )}
      </main>
    </div>
  );
}
