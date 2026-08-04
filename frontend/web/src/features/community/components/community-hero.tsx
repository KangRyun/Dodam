import Link from "next/link";

/**
 * 커뮤니티 피드 상단의 스케치북 히어로.
 *
 * 배경은 도담 스타일 손그림 스케치북 일러스트(`/community-hero.png`)이고,
 * 문구는 빈 페이지 위에 오버레이한다(이미지에는 글자를 넣지 않는다).
 */
export function CommunityHero() {
  return (
    <section className="community-hero" aria-label="도담 커뮤니티 소개">
      <div className="community-hero-inner">
        <span className="community-hero-eyebrow">🖍️ 도담이랑 그림 이야기</span>
        <h1>
          그림으로 나누는{" "}
          <span className="community-hero-highlight">우리 아이 마음</span>
        </h1>
        <p>그림 이야기·활동 후기를 도란도란 나누는 곳이에요.</p>
        <Link
          className="community-button community-button-primary"
          href="/community/write"
        >
          ✎ 이야기 쓰기
        </Link>
      </div>
    </section>
  );
}
