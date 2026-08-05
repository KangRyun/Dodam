import { LEGAL_LINKS } from "../constants";

/**
 * 루트 랜딩 footer.
 *
 * 약관·정책 링크는 루트 계약(S15P11B209-769)의 필수 요소라 랜딩 디자인이 바뀌어도 유지한다.
 * `/legal/*` 는 nginx 정적 페이지라 next/link 를 쓰지 않는다.
 */
export function LandingFooter() {
  return (
    <footer className="landing-footer">
      <div className="landing-container">
        <nav className="landing-footer-links" aria-label="약관과 정책">
          {LEGAL_LINKS.map((link) => (
            <a key={link.href} href={link.href}>
              {link.label}
            </a>
          ))}
        </nav>
        <p>도담은 아이의 그림 활동을 기록하는 서비스입니다.</p>
        <p>© 도담</p>
      </div>
    </footer>
  );
}
