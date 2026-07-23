import { notFound } from "next/navigation";

import { CommunityHeader } from "@/features/community/components/community-header";
import { CommunityPostDetail } from "@/features/community/components/community-post-detail";
import { MockCommunityRepository } from "@/features/community/community";

type CommunityPostDetailPageProps = {
  params: Promise<{ postId: string }>;
};

export default async function CommunityPostDetailPage({
  params,
}: CommunityPostDetailPageProps) {
  const { postId } = await params;
  const parsedPostId = Number(postId);
  if (!Number.isInteger(parsedPostId) || parsedPostId <= 0) notFound();

  const repository = new MockCommunityRepository();
  const post = await repository.getPost(parsedPostId);
  if (post === null) notFound();

  return (
    <div className="community-page">
      <CommunityHeader />
      <CommunityPostDetail post={post} />
    </div>
  );
}
