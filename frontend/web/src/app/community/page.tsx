import {
  CommunityCategoryTabs,
  parseCommunityCategory,
} from "@/features/community/components/community-category-tabs";
import { CommunityFeed } from "@/features/community/components/community-feed";
import { CommunityShell } from "@/features/community/components/community-shell";
import { CommunitySidebarContent } from "@/features/community/components/community-sidebar-content";
import { MockCommunityRepository } from "@/features/community/community";

type CommunityPageProps = {
  searchParams: Promise<{ category?: string }>;
};

export default async function CommunityPage({
  searchParams,
}: CommunityPageProps) {
  const { category } = await searchParams;
  const selectedCategory = parseCommunityCategory(category);
  const repository = new MockCommunityRepository();
  const feed = await repository.getFeed({ category: selectedCategory });

  return (
    <CommunityShell
      navigation={
        <CommunityCategoryTabs selectedCategory={selectedCategory} />
      }
      sidebar={
        <CommunitySidebarContent
          profile={feed.profile}
          popularTags={feed.popularTags}
        />
      }
    >
      <CommunityFeed posts={feed.posts} />
    </CommunityShell>
  );
}
