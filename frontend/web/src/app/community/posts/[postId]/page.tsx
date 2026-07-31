import { notFound } from "next/navigation";

import { CommunityPostDetailView } from "@/features/community/components/community-post-detail-view";

type CommunityPostDetailPageProps = {
  params: Promise<{ postId: string }>;
};

export default async function CommunityPostDetailPage({
  params,
}: CommunityPostDetailPageProps) {
  const { postId } = await params;
  const parsedPostId = Number(postId);
  if (!Number.isInteger(parsedPostId) || parsedPostId <= 0) notFound();

  return <CommunityPostDetailView postId={parsedPostId} />;
}
