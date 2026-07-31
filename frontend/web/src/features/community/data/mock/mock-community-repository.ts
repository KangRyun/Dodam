import { mockCommunityFeed } from "@/features/community/data/mock/mock-community-data";
import type {
  CommunityFeed,
  CommunityPost,
  CommunityPostFilter,
  CreateCommunityPostInput,
  UpdateCommunityPostInput,
} from "@/features/community/domain/community-models";
import type { CommunityRepository } from "@/features/community/domain/community-repository";

type MockCommunityRepositoryOptions = {
  delay?: number;
};

export class MockCommunityRepository implements CommunityRepository {
  private nextId = 9000;

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
    const post = mockCommunityFeed.posts.find((item) => item.id === postId);
    return post ? { ...post, editableByMe: true } : null;
  }

  async createPost(input: CreateCommunityPostInput): Promise<CommunityPost> {
    await this.wait();
    return this.buildPost(this.nextId++, input);
  }

  async updatePost(
    postId: number,
    input: UpdateCommunityPostInput,
  ): Promise<CommunityPost> {
    await this.wait();
    return this.buildPost(postId, input);
  }

  async deletePost(): Promise<void> {
    await this.wait();
  }

  /** 작성·수정 입력을 표시용 게시글 형태로 조립하는 로컬 헬퍼. */
  private buildPost(
    id: number,
    input: CreateCommunityPostInput | UpdateCommunityPostInput,
  ): CommunityPost {
    return {
      id,
      category: input.postType,
      title: input.title,
      excerpt: input.content.slice(0, 90),
      content: input.content,
      author: mockCommunityFeed.posts[0]?.author ?? {
        id: 0,
        nickname: "나",
        role: "GUARDIAN",
        avatar: "🌱",
      },
      tags: [],
      isAnonymous: input.anonymous,
      isLiked: false,
      likeCount: 0,
      commentCount: 0,
      viewCount: 0,
      createdAt: mockCommunityFeed.posts[0]?.createdAt ?? "2026-01-01T00:00:00Z",
      editableByMe: true,
      comments: [],
    };
  }

  private async wait() {
    const delay = this.options.delay ?? 0;
    if (delay > 0) {
      await new Promise((resolve) => setTimeout(resolve, delay));
    }
  }
}
