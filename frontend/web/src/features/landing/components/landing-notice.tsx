import type { ReactNode } from "react";

/**
 * AI 한계 안내 박스(가드레일 9절).
 *
 * 문구는 타협 불가라 눈에 띄는 위치에 두지만, 문장 전체를 굵게 하거나 강한 색으로
 * 경고하지는 않는다 — 보호자를 불안하게 만들지 않으면서 사실을 분명히 적는다.
 */
export function LandingNotice({ children }: { children: ReactNode }) {
  return (
    <p className="landing-notice">
      <svg
        className="landing-notice-icon"
        viewBox="0 0 20 20"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.6"
        aria-hidden="true"
      >
        <circle cx="10" cy="10" r="8" />
        <path d="M10 9v5" strokeLinecap="round" />
        <path d="M10 6.4v.6" strokeLinecap="round" />
      </svg>
      <span>{children}</span>
    </p>
  );
}
