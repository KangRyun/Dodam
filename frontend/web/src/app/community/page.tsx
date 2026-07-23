import { CommunityShell } from "@/features/community/components/community-shell";

export default function CommunityPage() {
  return (
    <CommunityShell
      navigation={
        <div className="h-10" aria-label="커뮤니티 카테고리 영역" />
      }
      sidebar={
        <>
          <section className="community-sidebar-card" aria-labelledby="profile-title">
            <h2 id="profile-title">내 커뮤니티</h2>
            <p>로그인 사용자 정보가 표시될 영역이에요.</p>
          </section>
          <section className="community-sidebar-card" aria-labelledby="tag-title">
            <h2 id="tag-title">인기 태그</h2>
            <p>커뮤니티 인기 태그가 표시될 영역이에요.</p>
          </section>
        </>
      }
    >
      <section className="community-empty-state" aria-labelledby="feed-title">
        <div className="community-empty-icon" aria-hidden="true">
          ✎
        </div>
        <h1 id="feed-title">마음그림 커뮤니티</h1>
        <p>보호자와 전문가의 이야기를 준비하고 있어요.</p>
      </section>
    </CommunityShell>
  );
}
