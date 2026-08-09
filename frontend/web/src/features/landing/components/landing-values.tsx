import Image from "next/image";

import { CHAR } from "../constants";

const CARDS = [
  {
    hero: false,
    top: "t-yellow",
    src: CHAR.valDraw,
    w: 300,
    h: 200,
    kicker: "그리기",
    title: "그리는 과정을 함께 남겨요",
    body: "캔버스에 그리거나 종이 그림을 찍어 올리면 결과와 과정이 같이 저장돼요.",
  },
  {
    hero: true,
    top: "t-blue",
    src: CHAR.valTalk,
    w: 300,
    h: 194,
    kicker: "이야기",
    title: "도담이가 그림을 보고 물어봐요",
    body: "아이는 말이나 선택지로 답할 수 있고, 그 답이 기록에 함께 담겨요.",
  },
  {
    hero: false,
    top: "t-green",
    src: CHAR.valRecord,
    w: 300,
    h: 200,
    kicker: "돌아보기",
    title: "활동별로 모아 보여줘요",
    body: "보호자는 어떤 활동을 했고 무엇을 이야기했는지 활동 단위로 확인해요.",
  },
];

export function LandingValues() {
  return (
    <section className="landing-section" aria-labelledby="landing-values-title">
      <div className="landing-container">
        <div className="landing-section-head">
          <h2 id="landing-values-title">도담이 남기는 세 가지</h2>
        </div>

        <div className="crayon-cards">
          {CARDS.map((card) => (
            <article
              className={`crayon-card${card.hero ? " is-hero" : ""}`}
              key={card.title}
            >
              <div className={`crayon-card-top ${card.top}`}>
                <Image
                  src={card.src}
                  alt=""
                  aria-hidden="true"
                  width={card.w}
                  height={card.h}
                />
              </div>
              <span className="crayon-kicker">{card.kicker}</span>
              <h3>{card.title}</h3>
              <p>{card.body}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
