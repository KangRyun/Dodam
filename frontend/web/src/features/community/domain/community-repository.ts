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
  /** COMM-16 게시글 댓글 목록 조회. */
  getComments(postId: number): Promise<readonly CommunityComment[]>;
  /** COMM-08 댓글 작성. 생성된 댓글을 반환한다. */
  createComment(
    postId: number,
    input: CreateCommunityCommentInput,
  ): Promise<CommunityComment>;
  /** COMM-09 댓글 수정. 수정된 댓글을 반환한다. */
  updateComment(
    commentId: number,
    input: UpdateCommunityCommentInput,
  ): Promise<CommunityComment>;
  /** COMM-10 댓글 삭제. */
  deleteComment(commentId: number): Promise<void>;
}
