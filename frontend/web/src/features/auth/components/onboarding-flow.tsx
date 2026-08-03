"use client";

import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";

import { authRepository } from "@/features/auth/data/auth-repository-factory";
import type {
  AuthUser,
  ConsentTerm,
  UserRole,
} from "@/features/auth/domain/auth-models";
import { useAuthStore } from "@/features/auth/hooks/use-auth-store";

type Step = "profile" | "email" | "consent";

const ROLE_OPTIONS: { value: UserRole; label: string; description: string }[] = [
  { value: "GUARDIAN", label: "보호자", description: "아이의 활동과 리포트를 확인해요." },
  { value: "EXPERT", label: "전문가", description: "분석 결과를 함께 살펴봐요." },
];

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function OnboardingFlow({ user }: { user: AuthUser }) {
  const router = useRouter();
  const setUser = useAuthStore((state) => state.setUser);

  const needsEmail = user.emailRequired;
  const steps = useMemo<Step[]>(
    () => (needsEmail ? ["profile", "email", "consent"] : ["profile", "consent"]),
    [needsEmail],
  );

  const [stepIndex, setStepIndex] = useState(0);
  const step = steps[stepIndex];

  const [role, setRole] = useState<UserRole | null>(user.role ?? null);
  const [nickname, setNickname] = useState(user.nickname ?? "");
  const [email, setEmail] = useState(user.email ?? "");

  const [terms, setTerms] = useState<ConsentTerm[] | null>(null);
  const [agreed, setAgreed] = useState<Record<number, boolean>>({});
  const [termsError, setTermsError] = useState<string | null>(null);

  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    authRepository
      .getTerms()
      .then((list) => {
        if (active) setTerms(list);
      })
      .catch(() => {
        if (active) setTermsError("약관을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.");
      });
    return () => {
      active = false;
    };
  }, []);

  const requiredUnmet = (terms ?? []).some(
    (term) => term.required && !agreed[term.termId],
  );

  function goNext() {
    setError(null);
    if (step === "profile") {
      if (role == null) return setError("역할을 선택해 주세요.");
      if (nickname.trim().length === 0) return setError("닉네임을 입력해 주세요.");
    }
    if (step === "email") {
      if (!EMAIL_PATTERN.test(email.trim()))
        return setError("올바른 이메일을 입력해 주세요.");
    }
    setStepIndex((index) => Math.min(index + 1, steps.length - 1));
  }

  async function submit() {
    setError(null);
    if (role == null) return setError("역할을 선택해 주세요.");
    if (requiredUnmet) return setError("필수 약관에 동의해 주세요.");
    const finalEmail = (needsEmail ? email : (user.email ?? email)).trim();
    if (!EMAIL_PATTERN.test(finalEmail))
      return setError("이메일 정보가 필요해요.");

    setSubmitting(true);
    try {
      const consents = (terms ?? []).map((term) => ({
        termId: term.termId,
        action: agreed[term.termId] ? ("AGREE" as const) : ("WITHDRAW" as const),
      }));
      const updated = await authRepository.completeOnboarding({
        role,
        nickname: nickname.trim(),
        email: finalEmail,
        consents,
      });
      setUser(updated);
      router.replace("/community");
    } catch (submitError) {
      setError(
        submitError instanceof Error
          ? submitError.message
          : "가입을 완료하지 못했어요. 다시 시도해 주세요.",
      );
      setSubmitting(false);
    }
  }

  return (
    <div className="w-full max-w-md">
      <p className="mb-1 text-xs font-medium text-neutral-400">
        {stepIndex + 1} / {steps.length}
      </p>
      <h1 className="mb-6 text-xl font-extrabold text-neutral-900">
        {step === "profile" && "기본 정보를 알려주세요"}
        {step === "email" && "이메일을 입력해 주세요"}
        {step === "consent" && "약관에 동의해 주세요"}
      </h1>

      {step === "profile" && (
        <div className="flex flex-col gap-4">
          <div className="flex flex-col gap-2">
            {ROLE_OPTIONS.map((option) => (
              <button
                key={option.value}
                type="button"
                onClick={() => setRole(option.value)}
                aria-pressed={role === option.value}
                className={`rounded-xl border px-4 py-3 text-left transition ${
                  role === option.value
                    ? "border-emerald-500 bg-emerald-50"
                    : "border-neutral-200 hover:border-neutral-300"
                }`}
              >
                <span className="block font-semibold text-neutral-900">
                  {option.label}
                </span>
                <span className="block text-sm text-neutral-500">
                  {option.description}
                </span>
              </button>
            ))}
          </div>
          <label className="flex flex-col gap-1 text-sm">
            <span className="font-medium text-neutral-700">닉네임</span>
            <input
              value={nickname}
              onChange={(event) => setNickname(event.target.value)}
              maxLength={50}
              placeholder="커뮤니티에서 쓸 이름"
              className="h-11 rounded-xl border border-neutral-300 px-3 outline-none focus:border-emerald-500"
            />
          </label>
        </div>
      )}

      {step === "email" && (
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium text-neutral-700">이메일</span>
          <input
            type="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            maxLength={255}
            placeholder="you@example.com"
            className="h-11 rounded-xl border border-neutral-300 px-3 outline-none focus:border-emerald-500"
          />
          <span className="text-xs text-neutral-400">
            소셜 계정에서 이메일을 받지 못해 한 번만 확인이 필요해요.
          </span>
        </label>
      )}

      {step === "consent" && (
        <div className="flex flex-col gap-2">
          {termsError && <p className="text-sm text-red-600">{termsError}</p>}
          {terms == null && !termsError && (
            <p className="text-sm text-neutral-400">약관을 불러오는 중…</p>
          )}
          {(terms ?? []).map((term) => (
            <label
              key={term.termId}
              className="flex items-start gap-3 rounded-xl border border-neutral-200 px-4 py-3"
            >
              <input
                type="checkbox"
                checked={agreed[term.termId] ?? false}
                onChange={(event) =>
                  setAgreed((prev) => ({
                    ...prev,
                    [term.termId]: event.target.checked,
                  }))
                }
                className="mt-1"
              />
              <span className="text-sm text-neutral-800">
                <span className="font-medium">
                  {term.required ? "[필수] " : "[선택] "}
                  {term.title}
                </span>
                {term.contentUrl && (
                  <a
                    href={term.contentUrl}
                    target="_blank"
                    rel="noreferrer"
                    className="ml-2 text-xs text-emerald-600 underline"
                  >
                    보기
                  </a>
                )}
              </span>
            </label>
          ))}
        </div>
      )}

      {error && <p className="mt-4 text-sm text-red-600">{error}</p>}

      <div className="mt-6 flex gap-3">
        {stepIndex > 0 && (
          <button
            type="button"
            onClick={() => setStepIndex((index) => Math.max(index - 1, 0))}
            className="h-12 flex-1 rounded-xl border border-neutral-300 font-semibold text-neutral-700"
          >
            이전
          </button>
        )}
        {step === "consent" ? (
          <button
            type="button"
            disabled={submitting || terms == null || requiredUnmet}
            onClick={submit}
            className="h-12 flex-1 rounded-xl bg-emerald-600 font-semibold text-white transition hover:bg-emerald-700 disabled:opacity-50"
          >
            {submitting ? "가입 중…" : "가입 완료"}
          </button>
        ) : (
          <button
            type="button"
            onClick={goNext}
            className="h-12 flex-1 rounded-xl bg-emerald-600 font-semibold text-white transition hover:bg-emerald-700"
          >
            다음
          </button>
        )}
      </div>
    </div>
  );
}
