"use client";

import Link from "next/link";

import { useCommunityViewer } from "@/features/community/hooks/use-community-viewer";
import type { CommunityProfile } from "@/features/community/domain/community-models";

export function CommunitySidebarContent({
  profile,
  popularTags,
}: {
  profile: CommunityProfile;
  popularTags: readonly string[];
}) {
  // 프로필 카드의 이름은 하드코딩 기본값이 아니라 실제 로그인 사용자에서 가져온다.
  const { nickname } = useCommunityViewer();

  return (
    <>
      <section
        className="community-sidebar-card community-profile-card"
        aria-labelledby="profile-title"
      >
        <div className="community-profile-summary">
          <div className="community-profile-avatar" aria-hidden="true">
            {profile.avatar}
          </div>
          <div>
            <h2 id="profile-title">{nickname}</h2>
          </div>
        </div>
        <div className="community-profile-menu" aria-label="내 커뮤니티 메뉴">
          <Link href="/community/profile"><span>👤 내 프로필</span><span>›</span></Link>
          <Link href="/community/my-posts"><span>📝 내가 쓴 글</span><span>›</span></Link>
          <Link href="/community/liked-posts"><span>♥ 좋아요 한 글</span><span>›</span></Link>
          <Link href="/community/settings"><span>⚙ 설정</span><span>›</span></Link>
        </div>
      </section>

      <section className="community-sidebar-card" aria-labelledby="tag-title">
        <h2 id="tag-title">인기 태그</h2>
        <div className="community-popular-tags">
          {popularTags.map((tag) => (
            <span key={tag}>#{tag}</span>
          ))}
        </div>
      </section>
    </>
  );
}
