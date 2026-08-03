import type {
  CommunityProfile,
} from "@/features/community/domain/community-models";
import Link from "next/link";

const providerLabels: Record<CommunityProfile["connectedProvider"], string> = {
  KAKAO: "카카오 연결",
  GOOGLE: "구글 연결",
  NAVER: "네이버 연결",
};

export function CommunitySidebarContent({
  profile,
  popularTags,
}: {
  profile: CommunityProfile;
  popularTags: readonly string[];
}) {
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
            <h2 id="profile-title">{profile.nickname}</h2>
            <p>{providerLabels[profile.connectedProvider]}</p>
          </div>
        </div>
        <div className="community-profile-menu" aria-label="내 커뮤니티 메뉴">
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
