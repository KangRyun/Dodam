/* eslint-disable @next/next/no-img-element -- 브랜드 히어로 아트는 절대배치·퍼센트 크기라
   next/image 로 감싸면 오히려 복잡해진다. 최적화가 필요한 콘텐츠 이미지도 아니다. */
import type { Metadata } from "next";

import { SocialLoginButtons } from "@/features/auth/components/social-login-buttons";

export const metadata: Metadata = {
  title: "로그인 — 도담 커뮤니티",
  description: "소셜 계정으로 도담 커뮤니티에 로그인하거나 가입하세요.",
};

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;

  return (
    <main className="login">
      {/* 브랜드 패널 — 넓은 화면에선 좌측, 좁은 화면에선 상단 히어로. 앱 로그인과 동일한
          골드 그라디언트 + 워드마크 + 손그림 + 그림 그리는 도담이. */}
      <section className="login-brand" aria-hidden="true">
        <img
          className="login-doodle login-doodle-dino"
          src="/characters/doodle_dino.png"
          alt=""
        />
        <img
          className="login-doodle login-doodle-tree"
          src="/characters/doodle_tree.png"
          alt=""
        />
        <img
          className="login-doodle login-doodle-sun"
          src="/characters/doodle_sun.png"
          alt=""
        />
        <div className="login-wordmark">
          <span className="login-wordmark-title">도담</span>
          <span className="login-wordmark-tagline">
            그림으로 시작하는
            <br />
            우리 아이와의 대화
          </span>
        </div>
        <img
          className="login-mascot"
          src="/characters/dodam_drawing.png"
          alt="그림 그리는 도담이"
        />
      </section>

      <section className="login-panel">
        <div className="login-form">
          <div className="login-welcome">
            <h1 className="login-welcome-title">반가워요</h1>
            <p className="login-welcome-sub">
              소셜 계정으로 로그인하고 도담을 시작해요.
            </p>
          </div>

          {error ? (
            <p role="alert" className="login-error">
              {error}
            </p>
          ) : null}

          <div className="login-divider">
            <span>소셜 계정으로 시작</span>
          </div>

          <SocialLoginButtons />

          <p className="login-signup-note">회원가입도 소셜 로그인으로 진행돼요</p>

          <p className="login-policy">
            계속하면 <a href="/legal/terms/">이용약관</a> 및{" "}
            <a href="/legal/privacy/">개인정보 처리방침</a>에 동의합니다.
          </p>
        </div>
      </section>
    </main>
  );
}
