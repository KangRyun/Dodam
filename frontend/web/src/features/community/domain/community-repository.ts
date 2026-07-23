import type {
  CommunityFeed,
  CommunityPost,
  CommunityPostFilter,
} from "@/features/community/domain/community-models";

export interface CommunityRepository {
  getFeed(filter?: CommunityPostFilter): Promise<CommunityFeed>;
  getPost(postId: number): Promise<CommunityPost | null>;
}
