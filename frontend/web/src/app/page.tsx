import type { Metadata } from "next";

import Link from "next/link";

export const metadata: Metadata = {
  title: "도담 — 아이의 마음을 그림으로 만나요",
  description:
    "아이가 그림을 그리는 동안 AI 캐릭터가 말을 걸고, 그 과정과 이야기를 모아 보호자에게 관찰 리포트를 전해 드려요. 진단이 아닌, 아이와의 대화를 여는 서비스입니다.",
};

const STEPS = [
  {
    icon: "🖍️",
    title: "자유롭게 그려요",
    description:
      "캔버스에 쓱쓱 그려도 좋고, 종이에 그린 그림을 찰칵 찍어도 좋아요. 아이는 그저 즐겁게 그리면 돼요.",
  },
  {
    icon: "💬",
    title: "곰돌이와 이야기해요",
    description:
      "AI 캐릭터가 그림을 보며 다정하게 말을 걸어요. 말로 대답해도, 골라서 답해도 괜찮아요.",
  },
  {
    icon: "📖",
    title: "마음 리포트를 받아요",
    description:
      "그림과 대화를 모아 “이런 모습이 보였어요”를 보호자님께 전해 드려요.",
  },
] as const;

export default function HomePage() {
  return (
    <main className="landing">
      <section className="landing-hero">
        <p className="landing-eyebrow">아동 미술 관찰 서비스</p>
        <h1 className="landing-title">아이의 마음을 그림으로 만나요</h1>
        <p className="landing-subtitle">
          아이가 그림을 그리는 동안 곰돌이 친구가 말을 걸어요. 그리는 과정과
          나눈 이야기를 모아, 아이 마음을 이해하는 실마리를 보호자님께 전해
          드려요.
        </p>
        <div className="landing-cta-row">
          {/* /download/ 는 Next 라우터 밖(nginx 정적 페이지)이라 next/link 를 쓰지 않는다 */}
          <a className="landing-cta landing-cta-primary" href="/download/">
            앱 다운로드
          </a>
          <Link className="landing-cta landing-cta-ghost" href="/community">
            커뮤니티 둘러보기
          </Link>
        </div>
      </section>

      <section className="landing-steps" aria-label="도담이 함께하는 방법">
        {STEPS.map((step) => (
          <article key={step.title} className="landing-step-card">
            <span className="landing-step-icon" aria-hidden="true">
              {step.icon}
            </span>
            <h2 className="landing-step-title">{step.title}</h2>
            <p className="landing-step-desc">{step.description}</p>
          </article>
        ))}
      </section>

      {/* 가드레일 9절 — AI 한계 고지는 타협 불가. 눈에 띄는 위치에 고정한다. */}
      <section className="landing-notice">
        <h2 className="landing-notice-title">도담의 약속</h2>
        <p className="landing-notice-body">
          도담의 AI 분석은 진단이 아니라 관찰 참고 자료예요. 아이를 판단하는
          도구가 아니라, 아이와의 대화를 여는 실마리로 사용해 주세요. 더 깊은
          도움이 필요할 때는 전문가와 연결해 드려요.
        </p>
      </section>

      <footer className="landing-footer">
        <nav className="landing-footer-links" aria-label="약관과 정책">
          {/* /legal/* 도 nginx 정적 페이지 — next/link 대상이 아니다 */}
          <a href="/legal/privacy/">개인정보처리방침</a>
          <a href="/legal/terms/">이용약관</a>
        </nav>
        <p className="landing-footer-copy">© 도담</p>
      </footer>
    </main>
  );
}
