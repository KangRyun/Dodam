"use client";

import {
  useRef,
  useState,
  type KeyboardEvent as ReactKeyboardEvent,
  type ReactNode,
} from "react";

import { LandingNotice } from "./landing-notice";

type Page = {
  num: string;
  cls: string;
  tabLabel: string;
  title: ReactNode;
  body: string;
  art: ReactNode;
};

const PAGES: Page[] = [
  {
    num: "01",
    cls: "p1",
    tabLabel: "표현에는 정답표를 붙이지 않아요",
    title: (
      <>
        <span className="crayon-mark">표현</span>에는 정답표를 붙이지 않아요
      </>
    ),
    body: "그림을 잘 그렸는지 평가하거나 점수로 나누지 않습니다.",
    art: (
      <svg viewBox="0 0 260 120" fill="none">
        <rect x="16" y="12" width="150" height="96" rx="8" fill="#fff" stroke="#cabf9f" strokeWidth="2" />
        <path className="draw-line" pathLength={1} d="M34 82 C54 42 78 92 96 60 C112 34 138 78 152 50" stroke="#e0a92e" strokeWidth="6" strokeLinecap="round" />
        <path className="draw-line" pathLength={1} d="M40 96 C70 82 120 98 150 88" stroke="#7fb0e0" strokeWidth="4.5" strokeLinecap="round" opacity="0.85" />
        <path d="M196 40 q10 -14 20 0 q10 14 -10 22 q-20 -8 -10 -22z" fill="#f4c2c2" opacity="0.55" />
      </svg>
    ),
  },
  {
    num: "02",
    cls: "p2",
    tabLabel: "AI보다 아이의 말이 먼저예요",
    title: (
      <>
        AI보다 <span className="crayon-mark">아이의 말</span>이 먼저예요
      </>
    ),
    body: "AI는 질문과 기록 정리를 돕고, 아이가 직접 들려준 이야기를 중심에 둡니다.",
    art: (
      <svg viewBox="0 0 260 120" fill="none">
        <g>
          <rect x="14" y="54" width="44" height="28" rx="8" fill="#eceff2" stroke="#9aa0a6" strokeWidth="2" />
          <text x="36" y="73" fontSize="13" fontWeight="700" textAnchor="middle" fill="#7c848c">
            AI
          </text>
        </g>
        <g className="promise-bubble">
          <rect x="78" y="12" width="168" height="74" rx="22" fill="#fff6da" stroke="#c9a24a" strokeWidth="2" />
          <path d="M104 86 l-6 22 26 -16 z" fill="#fff6da" stroke="#c9a24a" strokeWidth="2" />
          <circle cx="130" cy="49" r="7" fill="#e0a92e" />
          <circle cx="162" cy="49" r="7" fill="#e0a92e" />
          <circle cx="194" cy="49" r="7" fill="#e0a92e" />
        </g>
      </svg>
    ),
  },
  {
    num: "03",
    cls: "p3",
    tabLabel: "기록과 진단의 경계를 지켜요",
    title: (
      <>
        기록과 <span className="crayon-mark">진단의 경계</span>를 지켜요
      </>
    ),
    body: "도담의 기록은 보호자의 관찰을 돕는 자료이며, 전문적인 판단을 대신하지 않습니다.",
    art: (
      <svg viewBox="0 0 260 120" fill="none">
        <rect x="16" y="26" width="98" height="70" rx="10" fill="#fff7df" stroke="#e0b85a" strokeWidth="2.5" />
        <text x="65" y="65" fontSize="11" fontWeight="700" textAnchor="middle" fill="#a5822f">
          활동 기록장
        </text>
        <rect x="146" y="26" width="98" height="70" rx="10" fill="#f1f3f0" stroke="#b6beb5" strokeWidth="2.5" />
        <text x="195" y="65" fontSize="11" fontWeight="700" textAnchor="middle" fill="#5d6b62">
          전문가 영역
        </text>
        <line className="promise-boundary" x1="130" y1="18" x2="130" y2="104" stroke="#8a7a5a" strokeWidth="3" strokeDasharray="3 7" strokeLinecap="round" />
      </svg>
    ),
  },
];

export function LandingSafety() {
  const [current, setCurrent] = useState(0);
  const [fromLeft, setFromLeft] = useState(false);
  const prev = useRef(0);
  const tabRefs = useRef<Array<HTMLButtonElement | null>>([]);

  function select(i: number, focus: boolean) {
    setFromLeft(i < prev.current);
    prev.current = i;
    setCurrent(i);
    if (focus) tabRefs.current[i]?.focus();
  }

  function onKeyDown(e: ReactKeyboardEvent, i: number) {
    let n: number | null = null;
    if (e.key === "ArrowRight" || e.key === "ArrowDown") n = (i + 1) % PAGES.length;
    else if (e.key === "ArrowLeft" || e.key === "ArrowUp") n = (i - 1 + PAGES.length) % PAGES.length;
    else if (e.key === "Home") n = 0;
    else if (e.key === "End") n = PAGES.length - 1;
    if (n === null) return;
    e.preventDefault();
    select(n, true);
  }

  return (
    <section className="landing-section landing-safety" id="safety" aria-labelledby="promise-title">
      <div className="landing-container">
        <div className="landing-section-head">
          <h2 id="promise-title" className="crayon-underline">
            도담이 지키는 세 가지
          </h2>
          <p>항목을 눌러 하나씩 확인해 보세요.</p>
        </div>

        <div className="promise">
          <div className="promise-note">
            <span className="promise-clip" aria-hidden="true" />
            {PAGES.map((page, i) => {
              const active = i === current;
              const cls = active
                ? `promise-page ${page.cls} anim${fromLeft ? " from-left" : ""}`
                : `promise-page ${page.cls}`;
              return (
                <div
                  key={page.cls}
                  className={cls}
                  id={`pp${i + 1}`}
                  role="tabpanel"
                  aria-labelledby={`pt${i + 1}`}
                  tabIndex={0}
                  hidden={!active}
                >
                  <span className="promise-num" aria-hidden="true">
                    {page.num}
                  </span>
                  <h3>{page.title}</h3>
                  <p>{page.body}</p>
                  <div className="promise-art" aria-hidden="true">
                    {page.art}
                  </div>
                </div>
              );
            })}
          </div>

          <div className="promise-tabs" role="tablist" aria-label="도담 기록 원칙" aria-orientation="vertical">
            {PAGES.map((page, i) => {
              const active = i === current;
              return (
                <button
                  key={page.cls}
                  ref={(el) => {
                    tabRefs.current[i] = el;
                  }}
                  className={`promise-tab t${i + 1}${active ? " is-active" : ""}`}
                  id={`pt${i + 1}`}
                  role="tab"
                  aria-selected={active}
                  aria-controls={`pp${i + 1}`}
                  tabIndex={active ? 0 : -1}
                  onClick={() => select(i, false)}
                  onKeyDown={(e) => onKeyDown(e, i)}
                >
                  <span className="pt-num" aria-hidden="true">
                    {page.num}
                  </span>{" "}
                  {page.tabLabel}
                </button>
              );
            })}
          </div>
        </div>

        {/* 가드레일 9절 — AI 한계 고지. 문구를 바꾸면 home.spec.ts 도 함께 본다. */}
        <LandingNotice>
          도담이 쓰는 AI는 아이에게 건넬 질문을 만들고 기록을 정리하는 데
          쓰여요. 아이를 진단하거나 평가하지 않아요.
        </LandingNotice>
      </div>
    </section>
  );
}
