"use client";

import { useRouter } from "next/navigation";
import { use, useEffect, useRef } from "react";

import { saveSession } from "@/features/auth/data/session-store";
import type { AuthProviderId } from "@/features/auth/domain/auth-models";
import { useAuthStore } from "@/features/auth/hooks/use-auth-store";
import { OAUTH_PROVIDERS } from "@/features/auth/oauth/oauth-config";
import { completeOAuthLogin } from "@/features/auth/oauth/oauth-login-client";

export default function OAuthCallbackPage({
  params,
}: {
  params: Promise<{ provider: string }>;
}) {
  const { provider } = use(params);
  const router = useRouter();
  const started = useRef(false);

  useEffect(() => {
    if (started.current) return;
    started.current = true;

    const toLogin = (message: string) =>
      router.replace(`/login?error=${encodeURIComponent(message)}`);

    const search = new URLSearchParams(window.location.search);
    if (search.get("error")) {
      toLogin("로그인이 취소되었어요. 다시 시도해 주세요.");
      return;
    }
    const code = search.get("code");
    const state = search.get("state") ?? "";
    if (!OAUTH_PROVIDERS.includes(provider as AuthProviderId) || !code) {
      toLogin("로그인 정보를 확인하지 못했어요. 다시 시도해 주세요.");
      return;
    }

    void (async () => {
      try {
        const session = await completeOAuthLogin({
          provider: provider as AuthProviderId,
          code,
          state,
        });
        saveSession(session);
        useAuthStore.getState().setUser(session.user);
        const needsOnboarding =
          session.user.emailRequired || !session.user.onboardingCompleted;
        router.replace(needsOnboarding ? "/onboarding" : "/community");
      } catch (error) {
        toLogin(
          error instanceof Error
            ? error.message
            : "로그인에 실패했어요. 다시 시도해 주세요.",
        );
      }
    })();
  }, [provider, router]);

  return (
    <main className="flex min-h-dvh items-center justify-center bg-neutral-50 px-6">
      <p className="text-sm text-neutral-500">로그인 처리 중이에요…</p>
    </main>
  );
}
