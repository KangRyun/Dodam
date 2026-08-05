import Image from "next/image";

import { CHAR, FRIEND } from "../constants";

/**
 * 이용 흐름 4단계.
 *
 * 카드마다 주요 캐릭터는 하나만 둔다. 1단계는 아직 캐릭터가 없어 억지로 넣지 않고
 * 단순한 선형 종이 아이콘을 쓴다(S15P11B209-880 2차).
 * 캐릭터는 모두 1254×1254 정사각 원본이라 같은 박스에 contain 으로 담으면
 * 비율을 왜곡하지 않고 시각 크기·바닥선이 맞는다.
 */
const STEPS = [
  {
    title: "활동을 골라요",
    body: "오늘 할 그림 활동을 하나 선택해요.",
    art: null,
  },
  {
    title: "아이가 그려요",
    body: "캔버스에 그리거나 종이 그림을 찍어 올려요.",
    art: { src: FRIEND.crayon, alt: "크레용 친구 캐릭터" },
  },
  {
    title: "도담이와 이야기해요",
    body: "그림을 보고 물어보면 아이가 답해요.",
    art: { src: CHAR.child, alt: "크레파스를 든 도담이 캐릭터" },
  },
  {
    title: "보호자가 확인해요",
    body: "그림과 대화가 활동별로 정리돼요.",
    art: { src: FRIEND.sketchbook, alt: "연필을 든 스케치북 친구 캐릭터" },
  },
];

function PaperIcon() {
  return (
    <svg
      className="crayon-paper-icon"
      viewBox="0 0 32 32"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M8 4h11l5 5v19H8z" />
      <path d="M19 4v5h5" />
      <path d="M12 16h8M12 21h8" />
    </svg>
  );
}

export function LandingFlow() {
  return (
    <section
      className="landing-section landing-flow"
      id="flow"
      aria-labelledby="landing-flow-title"
    >
      <div className="landing-container">
        <div className="landing-flow-guide">
          <Image
            className="landing-flow-guide-img"
            src={CHAR.guide}
            alt="이용 흐름을 안내하는 노란 도담이 캐릭터"
            width={280}
            height={158}
          />
        </div>

        <div className="landing-section-head">
          <h2 id="landing-flow-title" className="crayon-underline">
            도담과 함께하는 네 단계
          </h2>
        </div>

        <div className="crayon-flow">
          <ol className="crayon-steps">
            {STEPS.map((step, index) => (
              <li className="crayon-paper" key={step.title}>
                <span className="crayon-peg" aria-hidden="true" />
                <span className="snum" aria-hidden="true">
                  {index + 1}
                </span>
                <h3>
                  <span className="sr-only">{index + 1}단계. </span>
                  {step.title}
                </h3>
                <p>{step.body}</p>
                <div className="crayon-paper-art">
                  {step.art ? (
                    <Image
                      className="crayon-paper-friend"
                      src={step.art.src}
                      alt=""
                      aria-hidden="true"
                      width={300}
                      height={300}
                    />
                  ) : (
                    <PaperIcon />
                  )}
                </div>
              </li>
            ))}
          </ol>
        </div>
      </div>
    </section>
  );
}
