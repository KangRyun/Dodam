import Image from "next/image";

import { CHAR } from "../constants";
import { LandingNotice } from "./landing-notice";

const REPORT_ITEMS = [
  { src: CHAR.repPalette, label: "완성한 그림" },
  { src: CHAR.repPencil, label: "그림을 그린 과정" },
  { src: CHAR.repSpeech, label: "아이가 설명한 내용" },
  { src: CHAR.repNotebook, label: "활동별 기록" },
];

export function LandingReport() {
  return (
    <section
      className="landing-section landing-report"
      id="report"
      aria-labelledby="landing-report-title"
    >
      <div className="landing-container landing-report-grid">
        <div className="landing-report-visual">
          <Image
            className="landing-report-img"
            src={CHAR.report}
            alt="활동 기록을 보여주는 도담이 캐릭터"
            width={300}
            height={350}
          />
        </div>

        <div>
          <h2 id="landing-report-title">활동 기록에는 무엇이 담기나요?</h2>
          <p className="landing-report-desc">
            하나의 활동에서 나온 그림과 대화를 함께 묶어 보여줘요.
          </p>

          <ul className="landing-report-list">
            {REPORT_ITEMS.map((item) => (
              <li key={item.label}>
                <Image
                  src={item.src}
                  alt=""
                  aria-hidden="true"
                  width={44}
                  height={44}
                />
                {item.label}
              </li>
            ))}
          </ul>

          {/* 가드레일 9절 — 비진단 고지. 문구를 바꾸면 home.spec.ts 도 함께 본다. */}
          <LandingNotice>
            도담의 기록은 의료적·심리적 진단이 아닌, 아이를 이해하고 대화를
            나누기 위한 참고 자료예요.
          </LandingNotice>
        </div>
      </div>
    </section>
  );
}
