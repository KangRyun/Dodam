import { parseCommunityCategory } from "@/features/community/components/community-category-tabs";
import { CommunityFeedView } from "@/features/community/components/community-feed-view";

type CommunityPageProps = {
  searchParams: Promise<{ category?: string }>;
};

export default async function CommunityPage({
  searchParams,
}: CommunityPageProps) {
  const { category } = await searchParams;
  const selectedCategory = parseCommunityCategory(category);

  return <CommunityFeedView category={selectedCategory} />;
}
