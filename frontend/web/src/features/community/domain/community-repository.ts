import type {
  CommunityFeed,
  CommunityPost,
  CommunityPostFilter,
  CreateCommunityPostInput,
  UpdateCommunityPostInput,
} from "@/features/community/domain/community-models";

export interface CommunityRepository {
  /** COMM-01 게시글 목록·피드 조회. */
  getFeed(filter?: CommunityPostFilter): Promise<CommunityFeed>;
  /** COMM-03 게시글 상세 조회. 없으면 `null`. */
  getPost(postId: number): Promise<CommunityPost | null>;
  /** COMM-02 게시글 작성. 생성된 게시글 상세를 반환한다. */
  createPost(input: CreateCommunityPostInput): Promise<CommunityPost>;
  /** COMM-04 게시글 수정(전체 교체). 수정된 게시글 상세를 반환한다. */
  updatePost(
    postId: number,
    input: UpdateCommunityPostInput,
  ): Promise<CommunityPost>;
  /** COMM-05 게시글 삭제(Soft Delete). */
  deletePost(postId: number): Promise<void>;
}
