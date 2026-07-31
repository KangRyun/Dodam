import { ApiCommunityRepository } from "@/features/community/data/api/api-community-repository";
import { MockCommunityRepository } from "@/features/community/data/mock/mock-community-repository";
import type { CommunityRepository } from "@/features/community/domain/community-repository";

/**
 * 커뮤니티 저장소를 만든다. 기본은 실제 백엔드(`ApiCommunityRepository`)이며,
 * 백엔드 없이 화면만 확인할 때는 `NEXT_PUBLIC_COMMUNITY_MOCK=1`로 목업을 쓴다.
 */
export function createCommunityRepository(): CommunityRepository {
  if (process.env.NEXT_PUBLIC_COMMUNITY_MOCK === "1") {
    return new MockCommunityRepository({ delay: 200 });
  }
  return new ApiCommunityRepository();
}

/** 앱 전역에서 재사용하는 단일 저장소 인스턴스. */
export const communityRepository = createCommunityRepository();
