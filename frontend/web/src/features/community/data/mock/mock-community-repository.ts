import { mockCommunityFeed } from "@/features/community/data/mock/mock-community-data";
import type {
  CommunityComment,
  CommunityFeed,
  CommunityPost,
  CommunityPostLikeResult,
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
  private readonly likesByPost = new Map<
    number,
    { liked: boolean; likeCount: number }
  >();

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

    const sortedPosts = [...posts].sort((left, right) => {
      if (filter.sort === "createdAt,asc") {
        return Date.parse(left.createdAt) - Date.parse(right.createdAt);
      }
      if (filter.sort === "likeCount,desc") {
        return right.likeCount - left.likeCount || right.id - left.id;
      }
      return Date.parse(right.createdAt) - Date.parse(left.createdAt);
    });

    return {
      ...mockCommunityFeed,
      posts: sortedPosts.map((post) => this.withLikeState(post)),
    };
  }

  async getMyPosts(): Promise<CommunityFeed> {
    const feed = await this.getFeed();
    return { ...feed, posts: feed.posts.filter((post) => post.editableByMe) };
  }

  async getLikedPosts(): Promise<CommunityFeed> {
    const feed = await this.getFeed();
    return { ...feed, posts: feed.posts.filter((post) => post.isLiked) };
  }

  async getPost(postId: number): Promise<CommunityPost | null> {
    await this.wait();
    const post = mockCommunityFeed.posts.find((item) => item.id === postId);
    return post
      ? { ...this.withLikeState(post), editableByMe: true }
      : null;
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

  async likePost(postId: number): Promise<CommunityPostLikeResult> {
    await this.wait();
    const post = this.findPost(postId);
    const current = this.getLikeState(post);
    const result = {
      postId,
      liked: true,
      likeCount: current.likeCount + (current.liked ? 0 : 1),
    };
    this.likesByPost.set(postId, result);
    return result;
  }

  async unlikePost(postId: number): Promise<void> {
    await this.wait();
    const post = this.findPost(postId);
    const current = this.getLikeState(post);
    this.likesByPost.set(postId, {
      liked: false,
      likeCount: Math.max(0, current.likeCount - (current.liked ? 1 : 0)),
    });
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

  private findPost(postId: number): CommunityPost {
    const post = mockCommunityFeed.posts.find((item) => item.id === postId);
    if (!post) throw new Error("게시글을 찾을 수 없어요.");
    return post;
  }

  private getLikeState(post: CommunityPost) {
    return (
      this.likesByPost.get(post.id) ?? {
        liked: post.isLiked,
        likeCount: post.likeCount,
      }
    );
  }

  private withLikeState(post: CommunityPost): CommunityPost {
    const state = this.getLikeState(post);
    return { ...post, isLiked: state.liked, likeCount: state.likeCount };
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
