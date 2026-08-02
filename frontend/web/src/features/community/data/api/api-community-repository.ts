import { apiRequest } from "@/lib/api/api-client";
import type {
  CommunityAuthor,
  CommunityAuthorRole,
  CommunityComment,
  CommunityFeed,
  CommunityPost,
  CommunityPostCategory,
  CommunityPostFilter,
  CommunityProfile,
  CreateCommunityCommentInput,
  CreateCommunityPostInput,
  UpdateCommunityCommentInput,
  UpdateCommunityPostInput,
} from "@/features/community/domain/community-models";
import type { CommunityRepository } from "@/features/community/domain/community-repository";

// --- 백엔드 응답 DTO (com.ssafy.b209.community.dto) ---

type PostAuthorDto = {
  userId: number | null;
  nickname: string | null;
};

type PostDetailAuthorDto = PostAuthorDto & {
  profileImageUrl: string | null;
};

type CommentAuthorDto = {
  userId: number | null;
  nickname: string | null;
  role: CommunityAuthorRole | null;
  profileImageUrl: string | null;
};

/** COMM-16/08/09 댓글 항목 DTO. (API 명세서 16.6-A) */
type CommentDto = {
  commentId: number;
  postId: number | null;
  author: CommentAuthorDto | null;
  anonymous: boolean;
  content: string;
  expertAnswer: boolean;
  accepted: boolean;
  editableByMe: boolean;
  createdAt: string;
  updatedAt: string;
};

type CommentPageDto = {
  content: CommentDto[];
  page: number;
  size: number;
  totalElements: number;
  totalPages: number;
  first: boolean;
  last: boolean;
  hasNext: boolean;
};

type PostListItemDto = {
  postId: number;
  postType: CommunityPostCategory;
  title: string;
  previewContent: string;
  author: PostAuthorDto | null;
  anonymous: boolean;
  likeCount: number;
  commentCount: number;
  likedByMe: boolean;
  createdAt: string;
  updatedAt: string;
};

type PostListPageDto = {
  content: PostListItemDto[];
  page: number;
  size: number;
  totalElements: number;
  totalPages: number;
  first: boolean;
  last: boolean;
  hasNext: boolean;
};

type PostDetailDto = {
  postId: number;
  postType: CommunityPostCategory;
  title: string;
  content: string;
  author: PostDetailAuthorDto | null;
  anonymous: boolean;
  attachments: unknown[];
  templateData: unknown[];
  likeCount: number;
  commentCount: number;
  likedByMe: boolean;
  editableByMe: boolean;
  createdAt: string;
  updatedAt: string;
};

/**
 * 백엔드가 목록·상세 응답에 담지 않는 표시용 필드의 기본값.
 *
 * 목업 모델(`role`, `avatar`, `tags`, `viewCount`, `answerStatus`, 댓글 목록)이
 * 실제 API 계약(COMM-01/03)보다 풍부하다. 계약에 없는 값은 아래 기본값으로 채우고,
 * 해당 필드를 실제로 제공하는 엔드포인트가 생기면 매핑을 보강한다.
 */
const DEFAULT_AVATAR = "🌱";
const ANONYMOUS_DISPLAY_NAME = "익명 보호자";
const EXCERPT_MAX_LENGTH = 90;

function toExcerpt(content: string): string {
  const normalized = content.replace(/\s+/g, " ").trim();
  return normalized.length > EXCERPT_MAX_LENGTH
    ? `${normalized.slice(0, EXCERPT_MAX_LENGTH)}…`
    : normalized;
}

function toAuthor(
  author: PostAuthorDto | PostDetailAuthorDto | null,
  anonymous: boolean,
): CommunityAuthor {
  if (anonymous || author === null) {
    return {
      id: 0,
      nickname: ANONYMOUS_DISPLAY_NAME,
      role: "GUARDIAN",
      avatar: "🙂",
    };
  }
  return {
    id: author.userId ?? 0,
    nickname: author.nickname ?? ANONYMOUS_DISPLAY_NAME,
    // 목록·상세 DTO에 작성자 역할이 없어 기본값으로 둔다(백엔드 미제공).
    role: "GUARDIAN",
    avatar: DEFAULT_AVATAR,
  };
}

function mapListItem(dto: PostListItemDto): CommunityPost {
  return {
    id: dto.postId,
    category: dto.postType,
    title: dto.title,
    excerpt: dto.previewContent,
    // 목록 응답에는 본문 전체가 없다. 상세 조회에서 채운다.
    content: "",
    author: toAuthor(dto.author, dto.anonymous),
    tags: [],
    isAnonymous: dto.anonymous,
    isLiked: dto.likedByMe,
    likeCount: dto.likeCount,
    commentCount: dto.commentCount,
    viewCount: 0,
    createdAt: dto.createdAt,
    comments: [],
  };
}

function toCommentAuthor(
  author: CommentAuthorDto | null,
  anonymous: boolean,
): CommunityAuthor {
  if (anonymous || author === null) {
    return {
      id: 0,
      nickname: ANONYMOUS_DISPLAY_NAME,
      role: "GUARDIAN",
      avatar: "🙂",
    };
  }
  return {
    id: author.userId ?? 0,
    nickname: author.nickname ?? ANONYMOUS_DISPLAY_NAME,
    role: author.role ?? "GUARDIAN",
    avatar: author.role === "EXPERT" ? "👩‍⚕️" : DEFAULT_AVATAR,
  };
}

function mapComment(dto: CommentDto): CommunityComment {
  return {
    id: dto.commentId,
    postId: dto.postId ?? undefined,
    author: toCommentAuthor(dto.author, dto.anonymous),
    content: dto.content,
    anonymous: dto.anonymous,
    isExpertAnswer: dto.expertAnswer,
    accepted: dto.accepted,
    // 댓글 "도움됐어요"는 아직 백엔드 계약에 없어 0으로 둔다.
    helpfulCount: 0,
    editableByMe: dto.editableByMe,
    createdAt: dto.createdAt,
    updatedAt: dto.updatedAt,
  };
}

function mapDetail(dto: PostDetailDto): CommunityPost {
  return {
    id: dto.postId,
    category: dto.postType,
    title: dto.title,
    excerpt: toExcerpt(dto.content),
    content: dto.content,
    author: toAuthor(dto.author, dto.anonymous),
    tags: [],
    isAnonymous: dto.anonymous,
    isLiked: dto.likedByMe,
    likeCount: dto.likeCount,
    commentCount: dto.commentCount,
    viewCount: 0,
    createdAt: dto.createdAt,
    editableByMe: dto.editableByMe,
    // 상세 응답에 댓글 목록이 없고 별도 조회 엔드포인트도 아직 없다(백엔드 미제공).
    comments: [],
  };
}

/**
 * 백엔드에 로그인 사용자 프로필·인기 태그 전용 엔드포인트가 아직 없어, 사이드바가
 * 깨지지 않도록 쓰는 임시 기본값. 프로필 조회 API가 생기면 교체한다.
 */
const PLACEHOLDER_PROFILE: CommunityProfile = {
  nickname: "커뮤니티",
  avatar: DEFAULT_AVATAR,
  connectedProvider: "KAKAO",
};

function buildFeedQuery(filter: CommunityPostFilter): string {
  const params = new URLSearchParams();
  if (filter.category) params.set("type", filter.category);
  const keyword = filter.query?.trim();
  if (keyword) params.set("keyword", keyword);
  const query = params.toString();
  return query.length > 0 ? `?${query}` : "";
}

/** 실제 백엔드(`/api/v1/posts`)에 연결하는 커뮤니티 저장소. */
export class ApiCommunityRepository implements CommunityRepository {
  async getFeed(filter: CommunityPostFilter = {}): Promise<CommunityFeed> {
    const page = await apiRequest<PostListPageDto>(
      `/posts${buildFeedQuery(filter)}`,
    );
    return {
      profile: PLACEHOLDER_PROFILE,
      popularTags: [],
      posts: page.content.map(mapListItem),
    };
  }

  async getPost(postId: number): Promise<CommunityPost | null> {
    try {
      const detail = await apiRequest<PostDetailDto>(`/posts/${postId}`);
      return mapDetail(detail);
    } catch (error) {
      // 없는 글은 404 → null. 다른 오류는 호출부가 처리하도록 다시 던진다.
      if (isNotFound(error)) return null;
      throw error;
    }
  }

  async createPost(input: CreateCommunityPostInput): Promise<CommunityPost> {
    const detail = await apiRequest<PostDetailDto>("/posts", {
      method: "POST",
      body: JSON.stringify(toRequestBody(input)),
    });
    return mapDetail(detail);
  }

  async updatePost(
    postId: number,
    input: UpdateCommunityPostInput,
  ): Promise<CommunityPost> {
    const detail = await apiRequest<PostDetailDto>(`/posts/${postId}`, {
      method: "PATCH",
      body: JSON.stringify(toRequestBody(input)),
    });
    return mapDetail(detail);
  }

  async deletePost(postId: number): Promise<void> {
    await apiRequest<void>(`/posts/${postId}`, { method: "DELETE" });
  }

  async getComments(postId: number): Promise<readonly CommunityComment[]> {
    // 통로 단계에서는 첫 페이지만 가져온다. 페이지네이션 UI가 생기면 확장한다.
    const page = await apiRequest<CommentPageDto>(
      `/posts/${postId}/comments?page=0&size=100&sort=createdAt,asc`,
    );
    return page.content.map(mapComment);
  }

  async createComment(
    postId: number,
    input: CreateCommunityCommentInput,
  ): Promise<CommunityComment> {
    const comment = await apiRequest<CommentDto>(`/posts/${postId}/comments`, {
      method: "POST",
      body: JSON.stringify({
        content: input.content,
        anonymous: input.anonymous,
      }),
    });
    return mapComment(comment);
  }

  async updateComment(
    commentId: number,
    input: UpdateCommunityCommentInput,
  ): Promise<CommunityComment> {
    const comment = await apiRequest<CommentDto>(`/comments/${commentId}`, {
      method: "PATCH",
      body: JSON.stringify({ content: input.content }),
    });
    return mapComment(comment);
  }

  async deleteComment(commentId: number): Promise<void> {
    await apiRequest<void>(`/comments/${commentId}`, { method: "DELETE" });
  }
}

function toRequestBody(input: CreateCommunityPostInput | UpdateCommunityPostInput) {
  return {
    postType: input.postType,
    title: input.title,
    content: input.content,
    anonymous: input.anonymous,
    templateData: input.templateData ?? null,
    attachments: input.attachments ?? [],
  };
}

function isNotFound(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "status" in error &&
    (error as { status: unknown }).status === 404
  );
}
