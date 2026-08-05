import Image from "next/image";

import { CHAR, FRIEND } from "../constants";

const ITEMS = [
  {
    cls: "n1",
    src: CHAR.icPencil,
    title: "그리는 순서",
    body: "그림을 그린 순서와 과정이 결과와 함께 남아요.",
  },
  {
    cls: "n2",
    src: CHAR.icSpeech,
    title: "아이가 한 말",
    body: "도담이의 질문에 아이가 답한 내용을 그대로 기록해요.",
  },
  {
    cls: "n3",
    src: CHAR.icClipboard,
    title: "활동별 정리",
    body: "따로 정리하지 않아도 활동 단위로 모여요.",
  },
];

export function LandingEmpathy() {
  return (
    <section
      className="landing-section"
      aria-labelledby="landing-empathy-title"
    >
      <div className="landing-container">
        <div className="landing-section-head">
          <h2 id="landing-empathy-title">
            완성된 그림 한 장에는
            <br />
            <span className="crayon-mark">담기지 않는 것들</span>이 있어요
          </h2>
        </div>

        {/* 지우개 친구는 여기 한 번만 쓴다 — 삭제·초기화 기능으로 읽히지 않도록
            "잘 그릴 필요가 없다"는 문구 옆에만 둔다(S15P11B209-880 2차). */}
        <div className="landing-reassure">
          <Image
            className="landing-reassure-img"
            src={FRIEND.eraser}
            alt=""
            aria-hidden="true"
            width={300}
            height={300}
          />
          <p>
            그림은 잘 그릴 필요가 없어요. 아이가 편한 방식으로 표현하면 충분해요.
          </p>
        </div>

        <div className="crayon-empathy">
          {ITEMS.map((item) => (
            <article className={`crayon-note ${item.cls}`} key={item.title}>
              <Image
                className="crayon-icon-img"
                src={item.src}
                alt=""
                aria-hidden="true"
                width={60}
                height={60}
              />
              <h3>{item.title}</h3>
              <p>{item.body}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
