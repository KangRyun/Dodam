export type CommunityAuthorRole = "GUARDIAN" | "EXPERT" | "ADMIN";

export type CommunityPostCategory =
  | "GUARDIAN_STORY"
  | "ACTIVITY_REVIEW"
  | "EXPERT_COLUMN"
  | "ART_ACTIVITY_RESOURCE"
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
