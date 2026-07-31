export type CommunityAuthorRole = "GUARDIAN" | "EXPERT" | "ADMIN";

/**
 * 게시글 유형. 백엔드 `PostType`(DB v1.2 `community_posts.post_type`)과 값이 1:1로 일치한다.
 * API 명세서 16.2-A 참고.
 */
export type CommunityPostCategory =
  | "GUARDIAN_STORY"
  | "ACTIVITY_REVIEW"
  | "EXPERT_COLUMN"
  | "ART_RESOURCE"
  | "DRAWING_GUIDE"
  | "EXPERT_QNA"
  | "NOTICE";

export type ExpertAnswerStatus = "WAITING" | "ANSWERED";

export type CommunityAuthor = {
  id: number;
  nickname: string;
  role: CommunityAuthorRole;
  avatar: string;
  credential?: string;
};

export type CommunityComment = {
  id: number;
  author: CommunityAuthor;
  content: string;
  helpfulCount: number;
  createdAt: string;
};

export type CommunityPost = {
  id: number;
  category: CommunityPostCategory;
  title: string;
  excerpt: string;
  content: string;
  author: CommunityAuthor;
  tags: readonly string[];
  imageUrl?: string;
  isAnonymous: boolean;
  isLiked: boolean;
  likeCount: number;
  commentCount: number;
  viewCount: number;
  createdAt: string;
  answerStatus?: ExpertAnswerStatus;
  /** 현재 로그인 사용자가 수정·삭제할 수 있는 글인지. 상세(COMM-03)에서만 채워진다. */
  editableByMe?: boolean;
  comments: readonly CommunityComment[];
};

export type CommunityProfile = {
  nickname: string;
  avatar: string;
  connectedProvider: "KAKAO" | "GOOGLE" | "NAVER";
};

export type CommunityFeed = {
  profile: CommunityProfile;
  popularTags: readonly string[];
  posts: readonly CommunityPost[];
};

export type CommunityPostFilter = {
  category?: CommunityPostCategory;
  query?: string;
};

/** 게시글 첨부(COMM-02/04). 현재 백엔드는 형식만 수용하고 저장하지 않는다. */
export type CommunityPostAttachmentInput = {
  fileId: string;
  type: "IMAGE";
};

/** 게시글 작성 요청 본문(COMM-02 `POST /posts`). */
export type CreateCommunityPostInput = {
  postType: CommunityPostCategory;
  title: string;
  content: string;
  anonymous: boolean;
  templateData?: unknown;
  attachments?: readonly CommunityPostAttachmentInput[];
};

/**
 * 게시글 수정 요청 본문(COMM-04 `PATCH /posts/{postId}`).
 *
 * 백엔드가 전체 교체(full replace) 방식이라 작성 요청과 형태가 같다.
 */
export type UpdateCommunityPostInput = CreateCommunityPostInput;
