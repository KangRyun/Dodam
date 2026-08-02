import { parseCommunityCategory } from "@/features/community/components/community-category-tabs";
import { CommunityFeedView } from "@/features/community/components/community-feed-view";
import type { CommunityPostSort } from "@/features/community/domain/community-models";

type CommunityPageProps = {
  searchParams: Promise<{ category?: string; query?: string; sort?: string }>;
};

const supportedSorts = new Set<CommunityPostSort>([
  "createdAt,desc",
  "createdAt,asc",
  "likeCount,desc",
]);

export default async function CommunityPage({
  searchParams,
}: CommunityPageProps) {
  const { category, query, sort } = await searchParams;
  const selectedCategory = parseCommunityCategory(category);
  const selectedSort = supportedSorts.has(sort as CommunityPostSort)
    ? (sort as CommunityPostSort)
    : "createdAt,desc";

  return (
    <CommunityFeedView
      category={selectedCategory}
      query={query?.trim().slice(0, 100) || undefined}
      sort={selectedSort}
    />
  );
}
