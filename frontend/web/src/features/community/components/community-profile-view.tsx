"use client";

import Link from "next/link";

import { CommunityShell } from "@/features/community/components/community-shell";
import { useCommunityViewer } from "@/features/community/hooks/use-community-viewer";

const PROFILE_AVATAR = "🌱";

/**
 * 내 프로필 화면.
 *
 * 상단 프로필(닉네임·아바타)과 함께 기존 "내가 쓴 글"·"좋아요 한 글" 목록으로
 * 이동하는 링크를 모아 보여준다. 목록 자체는 각 페이지를 재사용한다.
 */
export function CommunityProfileView() {
  const { nickname } = useCommunityViewer();

  return (
    <CommunityShell
      sidebar={null}
      navigation={
        <div className="community-personal-heading">
          <Link href="/community" aria-label="커뮤니티로 돌아가기">←</Link>
          <h1>내 프로필</h1>
        </div>
      }
    >
      <section
        className="community-settings-card community-profile-hero"
        aria-labelledby="community-profile-name"
      >
        <div className="community-profile-avatar" aria-hidden="true">
          {PROFILE_AVATAR}
        </div>
        <div>
          <h2 id="community-profile-name">{nickname}</h2>
          <p>내가 남긴 이야기와 좋아요를 모아 볼 수 있어요.</p>
        </div>
      </section>

      <nav className="community-profile-links" aria-label="내 활동">
        <Link href="/community/my-posts">
          <span>📝 내가 쓴 글</span>
          <span aria-hidden="true">›</span>
        </Link>
        <Link href="/community/liked-posts">
          <span>♥ 좋아요 한 글</span>
          <span aria-hidden="true">›</span>
        </Link>
        <Link href="/community/settings">
          <span>⚙ 설정</span>
          <span aria-hidden="true">›</span>
        </Link>
      </nav>
    </CommunityShell>
  );
}
