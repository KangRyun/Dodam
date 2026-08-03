import type { Metadata } from "next";

import { SocialLoginButtons } from "@/features/auth/components/social-login-buttons";

export const metadata: Metadata = {
  title: "로그인 — 도담 커뮤니티",
  description: "소셜 계정으로 도담 커뮤니티에 로그인하거나 가입하세요.",
};

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;

  return (
    <main className="flex min-h-dvh items-center justify-center bg-neutral-50 px-6 py-12">
      <div className="w-full max-w-sm">
        <div className="mb-8 text-center">
          <h1 className="text-2xl font-extrabold text-neutral-900">
            도담 커뮤니티
          </h1>
          <p className="mt-2 text-sm text-neutral-500">
            소셜 계정으로 로그인하면 앱과 같은 계정으로 이용할 수 있어요.
          </p>
        </div>

        {error ? (
          <p
            role="alert"
            className="mb-4 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700"
          >
            {error}
          </p>
        ) : null}

        <SocialLoginButtons />

        <p className="mt-6 text-center text-xs text-neutral-400">
          로그인 시 도담 서비스 약관과 개인정보 처리방침에 동의하게 됩니다.
        </p>
      </div>
    </main>
  );
}
