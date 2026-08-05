import Image from "next/image";

import { CHAR, DOWNLOAD_HREF } from "../constants";

export function LandingCta() {
  return (
    <section className="landing-final" aria-labelledby="landing-cta-title">
      <div className="landing-container">
        <div className="landing-final-card">
          <Image
            className="landing-final-img"
            src={CHAR.group}
            alt="여러 도담이 친구들이 함께 모여 있는 모습"
            width={560}
            height={373}
          />
          <h2 id="landing-cta-title">
            오늘 아이의 그림 이야기를 들어볼까요?
          </h2>
          {/* 실제 흐름은 로그인 → 프로필 선택 → 아이 등록 → 활동이라 "바로"라고 하지 않는다. */}
          <p>앱을 설치하고 아이 프로필을 만들면 첫 그림 활동을 시작할 수 있어요.</p>
          {/* /download/ 는 nginx 정적 페이지 — next/link 대상이 아니다 */}
          <a className="landing-btn landing-btn-primary" href={DOWNLOAD_HREF}>
            도담 시작하기
          </a>
        </div>
      </div>
    </section>
  );
}
