"use client";

import { useRouter } from "next/navigation";

import { CommunityHeader } from "@/features/community/components/community-header";
import { CommunityPostForm } from "@/features/community/components/community-post-form";
import { useCreateCommunityPost } from "@/features/community/hooks/use-community";

export function CommunityPostWriteView() {
  const router = useRouter();
  const createPost = useCreateCommunityPost();

  return (
    <div className="community-page">
      <CommunityHeader />
      <main className="community-detail-main">
        <CommunityPostForm
          heading="글쓰기"
          submitLabel="등록"
          pending={createPost.isPending}
          errorMessage={
            createPost.isError
              ? createPost.error instanceof Error
                ? createPost.error.message
                : "게시글을 등록하지 못했어요."
              : undefined
          }
          onSubmit={(input) =>
            createPost.mutate(input, {
              onSuccess: (post) => router.push(`/community/posts/${post.id}`),
            })
          }
        />
      </main>
    </div>
  );
}
