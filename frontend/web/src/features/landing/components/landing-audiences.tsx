import Image from "next/image";

import { CHAR } from "../constants";

const CHILD_POINTS = [
  "그림 활동 시작하기",
  "도담이의 질문에 답하기",
  "지난 그림 다시 보기",
];

const GUARDIAN_POINTS = [
  "활동 진행과 기록 관리",
  "완성된 그림과 대화 확인",
  "아이가 직접 들려준 이야기 확인",
  "보호자 전용 공간",
];

export function LandingAudiences() {
  return (
    <section
      className="landing-section"
      aria-labelledby="landing-audiences-title"
    >
      <div className="landing-container">
        <div className="landing-section-head">
          <h2 id="landing-audiences-title" className="crayon-underline">
            아이와 보호자가 보는 화면이 달라요
          </h2>
          <p>같은 활동을 각자에게 맞는 방식으로 만나요.</p>
        </div>

        <div className="crayon-audiences">
          <article className="crayon-aud child">
            <div className="crayon-aud-stage s-yellow">
              <Image
                src={CHAR.child}
                alt="크레파스를 든 아이 도담이 캐릭터"
                width={300}
                height={300}
              />
            </div>
            <span className="crayon-aud-label">아이에게는</span>
            <h3>그림을 그리고, 도담이와 이야기해요</h3>
            <p>
              아이가 편한 방식으로 그림을 그리고 자신의 이야기를 들려줄 수
              있어요.
            </p>
            <ul className="crayon-list">
              {CHILD_POINTS.map((point) => (
                <li key={point}>{point}</li>
              ))}
            </ul>
          </article>

          <article className="crayon-aud guardian">
            <div className="crayon-aud-stage s-green">
              <Image
                src={CHAR.guardian}
                alt="안경을 쓰고 공책을 든 보호자 도담이 캐릭터"
                width={300}
                height={300}
              />
            </div>
            <span className="crayon-aud-label">보호자에게는</span>
            <h3>아이의 기록을 한눈에 살펴봐요</h3>
            <p>완성된 그림과 대화, 활동별 기록을 모아볼 수 있어요.</p>
            <ul className="crayon-list">
              {GUARDIAN_POINTS.map((point) => (
                <li key={point}>{point}</li>
              ))}
            </ul>
          </article>
        </div>
      </div>
    </section>
  );
}
