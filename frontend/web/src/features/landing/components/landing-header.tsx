import Image from "next/image";
import Link from "next/link";
import type { ReactNode } from "react";

import { CHAR, DOWNLOAD_HREF, NAV_ITEMS } from "../constants";

function NavLink({ href, children }: { href: string; children: ReactNode }) {
  // 내부 라우트(/…)는 next/link, 같은 페이지 앵커(#…)는 일반 앵커
  if (href.startsWith("/")) {
    return <Link href={href}>{children}</Link>;
  }
  return <a href={href}>{children}</a>;
}

export function LandingHeader() {
  return (
    <header className="landing-header">
      <div className="landing-container landing-header-inner">
        <a className="landing-logo" href="#top" aria-label="도담 홈으로 이동">
          <Image
            className="landing-logo-img"
            src={CHAR.pyeonan}
            alt=""
            width={34}
            height={34}
            aria-hidden="true"
          />
          도담
        </a>

        <nav className="landing-nav" aria-label="주요 섹션">
          {NAV_ITEMS.map((item) => (
            <NavLink key={item.href} href={item.href}>
              {item.label}
            </NavLink>
          ))}
        </nav>

        <a className="landing-btn landing-btn-primary landing-header-cta" href={DOWNLOAD_HREF}>
          도담 시작하기
        </a>

        <details className="landing-menu">
          <summary aria-label="메뉴 열기">
            <svg
              className="landing-menu-icon"
              viewBox="0 0 20 20"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.6"
              strokeLinecap="round"
              aria-hidden="true"
            >
              <path d="M3 6h14M3 10h14M3 14h14" />
            </svg>
            메뉴
          </summary>
          <div className="landing-menu-panel">
            {NAV_ITEMS.map((item) => (
              <NavLink key={item.href} href={item.href}>
                {item.label}
              </NavLink>
            ))}
            <a className="landing-btn landing-btn-primary" href={DOWNLOAD_HREF}>
              도담 시작하기
            </a>
          </div>
        </details>
      </div>
    </header>
  );
}
