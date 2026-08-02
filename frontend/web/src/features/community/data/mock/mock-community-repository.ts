import { mockCommunityFeed } from "@/features/community/data/mock/mock-community-data";
import type {
  CommunityComment,
  CommunityFeed,
  CommunityPost,
  CommunityPostFilter,
  CreateCommunityCommentInput,
  CreateCommunityPostInput,
  UpdateCommunityCommentInput,
  UpdateCommunityPostInput,
} from "@/features/community/domain/community-models";
import type { CommunityRepository } from "@/features/community/domain/community-repository";

type MockCommunityRepositoryOptions = {
  delay?: number;
};

const MOCK_ME = {
  id: 999,
  nickname: "나",
  role: "GUARDIAN" as const,
  avatar: "🌱",
};

export class MockCommunityRepository implements CommunityRepository {
  private nextId = 9000;
  /** 게시글별 인메모리 댓글 저장소. 최초 접근 시 목업 데이터에서 시드한다. */
  private readonly commentsByPost = new Map<number, CommunityComment[]>();

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

  async getComments(postId: number): Promise<readonly CommunityComment[]> {
    await this.wait();
    return [...this.seedComments(postId)];
  }

  async createComment(
    postId: number,
    input: CreateCommunityCommentInput,
  ): Promise<CommunityComment> {
    await this.wait();
    const comment: CommunityComment = {
      id: this.nextId++,
      postId,
      author: MOCK_ME,
      content: input.content,
      anonymous: input.anonymous,
      isExpertAnswer: false,
      accepted: false,
      helpfulCount: 0,
      editableByMe: true,
      createdAt: new Date().toISOString(),
    };
    this.seedComments(postId).push(comment);
    return comment;
  }

  async updateComment(
    commentId: number,
    input: UpdateCommunityCommentInput,
  ): Promise<CommunityComment> {
    await this.wait();
    for (const comments of this.commentsByPost.values()) {
      const target = comments.find((comment) => comment.id === commentId);
      if (target) {
        target.content = input.content;
        target.updatedAt = new Date().toISOString();
        return target;
      }
    }
    throw new Error("댓글을 찾을 수 없어요.");
  }

  async deleteComment(commentId: number): Promise<void> {
    await this.wait();
    for (const [postId, comments] of this.commentsByPost.entries()) {
      const next = comments.filter((comment) => comment.id !== commentId);
      if (next.length !== comments.length) {
        this.commentsByPost.set(postId, next);
        return;
      }
    }
  }

  /** 게시글의 댓글 배열을 (없으면 목업에서 시드해) 돌려준다. */
  private seedComments(postId: number): CommunityComment[] {
    let comments = this.commentsByPost.get(postId);
    if (comments === undefined) {
      const post = mockCommunityFeed.posts.find((item) => item.id === postId);
      comments = (post?.comments ?? []).map((comment) => ({
        ...comment,
        postId,
        editableByMe: true,
      }));
      this.commentsByPost.set(postId, comments);
    }
    return comments;
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
