import type { Metadata } from "next";

import { LandingAudiences } from "@/features/landing/components/landing-audiences";
import { LandingCharacters } from "@/features/landing/components/landing-characters";
import { LandingCta } from "@/features/landing/components/landing-cta";
import { LandingEmpathy } from "@/features/landing/components/landing-empathy";
import { LandingFlow } from "@/features/landing/components/landing-flow";
import { LandingFooter } from "@/features/landing/components/landing-footer";
import { LandingHeader } from "@/features/landing/components/landing-header";
import { LandingHero } from "@/features/landing/components/landing-hero";
import { LandingReport } from "@/features/landing/components/landing-report";
import { LandingSafety } from "@/features/landing/components/landing-safety";
import { LandingValues } from "@/features/landing/components/landing-values";

import "@/features/landing/landing.css";

export const metadata: Metadata = {
  title: "도담 — 아이의 그림 속 이야기를 다정하게 기록해요",
  description:
    "도담은 완성된 그림뿐 아니라 그리는 과정과 아이가 직접 들려준 이야기를 함께 담아, 보호자가 아이의 하루를 더 가까이 이해하도록 돕는 활동 기록 서비스입니다. 진단이 아닌, 아이와의 대화를 여는 서비스입니다.",
};

/**
 * 공식 루트 랜딩(`/`).
 *
 * 루트 계약(S15P11B209-769)을 그대로 유지한다 — 앱 다운로드(`/download/`),
 * 커뮤니티 둘러보기(`/community`), 눈에 띄는 AI 비진단 안내, 약관·정책 링크.
 * 화면 구성만 S15P11B209-880의 크레용 디자인으로 교체했다.
 * 루트가 유일한 랜딩이므로 중복 `/landing` route 는 두지 않는다.
 */
export default function HomePage() {
  return (
    <div className="landing" id="top">
      <LandingHeader />
      <main>
        <LandingHero />
        <LandingEmpathy />
        <LandingValues />
        <LandingFlow />
        <LandingAudiences />
        <LandingReport />
        <LandingCharacters />
        <LandingSafety />
        <LandingCta />
      </main>
      <LandingFooter />
    </div>
  );
}
