import { mockCommunityFeed } from "@/features/community/data/mock/mock-community-data";
import type {
  CommunityFeed,
  CommunityPost,
  CommunityPostFilter,
} from "@/features/community/domain/community-models";
import type { CommunityRepository } from "@/features/community/domain/community-repository";

type MockCommunityRepositoryOptions = {
  delay?: number;
};

export class MockCommunityRepository implements CommunityRepository {
  constructor(private readonly options: MockCommunityRepositoryOptions = {}) {}

  async getFeed(filter: CommunityPostFilter = {}): Promise<CommunityFeed> {
    await this.wait();
    const query = filter.query?.trim().toLocaleLowerCase("ko-KR");
    const posts = mockCommunityFeed.posts.filter((post) => {
      const matchesCategory =
        filter.category === undefined || post.category === filter.category;
      const matchesQuery =
        query === undefined ||
        query.length === 0 ||
        [post.title, post.excerpt, post.content, ...post.tags].some((value) =>
          value.toLocaleLowerCase("ko-KR").includes(query),
        );
      return matchesCategory && matchesQuery;
    });

    return {
      ...mockCommunityFeed,
      posts,
    };
  }

  async getPost(postId: number): Promise<CommunityPost | null> {
    await this.wait();
    return mockCommunityFeed.posts.find((post) => post.id === postId) ?? null;
  }

  private async wait() {
    const delay = this.options.delay ?? 0;
    if (delay > 0) {
      await new Promise((resolve) => setTimeout(resolve, delay));
    }
  }
}
