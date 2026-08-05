import Image from "next/image";
import Link from "next/link";

import { CHAR, COMMUNITY_HREF, DOODLE, DOWNLOAD_HREF } from "../constants";

export function LandingHero() {
  return (
    <section
      className="landing-hero"
      id="about"
      aria-labelledby="landing-hero-title"
    >
      <div className="landing-container landing-hero-grid">
        <div className="landing-hero-copy">
          <span className="landing-eyebrow">아동 그림 활동 기록 서비스</span>

          <h1 className="landing-hero-title" id="landing-hero-title">
            아이의 그림과 이야기를,
            <br />
            <span className="landing-grad">함께 기록해요.</span>
          </h1>

          <p className="landing-hero-desc">
            완성된 그림만 남기지 않아요. 그리는 과정과 아이가 직접 설명한 이야기를
            활동별로 모아 보호자가 확인할 수 있어요.
          </p>

          <div className="landing-hero-actions">
            {/* /download/ 는 nginx 정적 페이지 — next/link 대상이 아니다 */}
            <a className="landing-btn landing-btn-primary" href={DOWNLOAD_HREF}>
              앱 다운로드
              <svg
                className="landing-btn-arrow"
                viewBox="0 0 20 20"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.8"
                strokeLinecap="round"
                strokeLinejoin="round"
                aria-hidden="true"
              >
                <path d="M4 10h11" />
                <path d="M11 6l4 4-4 4" />
              </svg>
            </a>
            <Link
              className="landing-btn landing-btn-secondary"
              href={COMMUNITY_HREF}
            >
              커뮤니티 둘러보기
            </Link>
          </div>

          <ul className="landing-hero-trust">
            <li>그리는 과정</li>
            <li>아이의 직접 설명</li>
            <li>활동별 기록</li>
          </ul>
        </div>

        {/* 히어로 아트는 오른쪽 열 안에만 둔다 — 왼쪽 제목·CTA 영역을 넘지 않는다.
            손그림은 로그인 화면과 같은 원본을 쓰고, 크기·각도를 서로 다르게 얹는다.
            모바일에서는 CSS 로 손그림을 감추고 도담이와 종이만 남긴다. */}
        <div className="landing-hero-visual">
          <span className="landing-hero-paper" aria-hidden="true" />

          <Image
            className="landing-doodle landing-doodle-sun"
            src={DOODLE.sun}
            alt=""
            aria-hidden="true"
            width={324}
            height={276}
          />
          <Image
            className="landing-doodle landing-doodle-tree"
            src={DOODLE.tree}
            alt=""
            aria-hidden="true"
            width={195}
            height={317}
          />
          <Image
            className="landing-doodle landing-doodle-dino"
            src={DOODLE.dino}
            alt=""
            aria-hidden="true"
            width={372}
            height={297}
          />

          <Image
            className="landing-hero-img"
            src={CHAR.child}
            alt="크레파스를 들고 손을 흔드는 도담이 캐릭터"
            width={380}
            height={380}
            priority
          />
        </div>
      </div>
    </section>
  );
}
