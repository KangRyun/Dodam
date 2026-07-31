import { notFound } from "next/navigation";

import { CommunityPostEditView } from "@/features/community/components/community-post-edit-view";

type CommunityPostEditPageProps = {
  params: Promise<{ postId: string }>;
};

export default async function CommunityPostEditPage({
  params,
}: CommunityPostEditPageProps) {
  const { postId } = await params;
  const parsedPostId = Number(postId);
  if (!Number.isInteger(parsedPostId) || parsedPostId <= 0) notFound();

  return <CommunityPostEditView postId={parsedPostId} />;
}
