"use client";

import { useState } from "react";

import type { AuthProviderId } from "@/features/auth/domain/auth-models";
import {
  isProviderConfigured,
  OAUTH_PROVIDERS,
} from "@/features/auth/oauth/oauth-config";
import { startOAuthLogin } from "@/features/auth/oauth/oauth-login-client";

type ProviderVisual = {
  label: string;
  iconSrc: string;
  /** 인라인 스타일(브랜드 규정 색). Tailwind 임의값 대신 앱과 동일하게 맞춘다. */
  style: React.CSSProperties;
};

// 앱(social_login_button.dart)의 색·라벨·아이콘과 1:1로 맞춘다.
const PROVIDER_VISUAL: Record<AuthProviderId, ProviderVisual> = {
  kakao: {
    label: "카카오로 시작하기",
    iconSrc: "/branding/kakao_symbol.svg",
    style: { backgroundColor: "#FEE500", color: "rgba(0,0,0,0.85)" },
  },
  google: {
    label: "Google로 시작하기",
    iconSrc: "/branding/google_g.svg",
    style: {
      backgroundColor: "#FFFFFF",
      color: "#1F1F1F",
      border: "1px solid #747775",
    },
  },
  naver: {
    label: "네이버로 시작하기",
    iconSrc: "/branding/naver_n.svg",
    style: { backgroundColor: "#03A94D", color: "#FFFFFF" },
  },
};

export function SocialLoginButtons() {
  // 리다이렉트가 시작되면 중복 클릭을 막기 위해 진행 중 제공자를 표시한다.
  const [pending, setPending] = useState<AuthProviderId | null>(null);

  return (
    <div className="flex w-full flex-col gap-2">
      {OAUTH_PROVIDERS.map((provider) => {
        const visual = PROVIDER_VISUAL[provider];
        const configured = isProviderConfigured(provider);
        const disabled = !configured || pending !== null;
        return (
          <button
            key={provider}
            type="button"
            disabled={disabled}
            aria-label={visual.label}
            style={visual.style}
            onClick={() => {
              setPending(provider);
              startOAuthLogin(provider);
            }}
            className="flex h-[52px] w-full items-center rounded-xl px-5 text-[15px] font-semibold transition disabled:cursor-not-allowed disabled:opacity-60"
          >
            {/* 로고는 좌측 고정, 라벨은 버튼 전체 기준 가운데(우측 20px 여백으로 대칭). */}
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={visual.iconSrc} alt="" width={20} height={20} />
            <span className="flex-1 text-center">
              {pending === provider ? "이동 중…" : visual.label}
            </span>
            <span className="w-5" aria-hidden />
          </button>
        );
      })}
    </div>
  );
}
