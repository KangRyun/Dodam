"use client";

import { useRouter } from "next/navigation";
import { useEffect } from "react";

import { OnboardingFlow } from "@/features/auth/components/onboarding-flow";
import { useAuthStore } from "@/features/auth/hooks/use-auth-store";

export default function OnboardingPage() {
  const router = useRouter();
  const user = useAuthStore((state) => state.user);

  useEffect(() => {
    // 새로고침 등으로 메모리 상태가 비면 sessionStorage에서 복원한다.
    if (useAuthStore.getState().user == null) {
      useAuthStore.getState().hydrate();
    }
    // 복원 후에도 로그인 사용자가 없으면 로그인 화면으로 보낸다.
    if (useAuthStore.getState().user == null) {
      router.replace("/login");
    }
  }, [router]);

  return (
    <main className="flex min-h-dvh items-center justify-center bg-neutral-50 px-6 py-12">
      {user != null ? (
        <OnboardingFlow user={user} />
      ) : (
        <p className="text-sm text-neutral-400">불러오는 중…</p>
      )}
    </main>
  );
}
