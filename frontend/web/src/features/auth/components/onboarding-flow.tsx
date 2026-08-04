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

const STEP_TITLE: Record<Step, string> = {
  profile: "기본 정보를 알려주세요",
  email: "이메일을 입력해 주세요",
  consent: "약관에 동의해 주세요",
};

// 백엔드 약관 응답에는 짧은 설명이 없어(title만) 앱 온보딩과 동일한 한 줄 설명을
// termCode 기준으로 붙인다. 코드는 백엔드 seed(V17)와 동일하다.
const CONSENT_DESCRIPTIONS: Record<string, string> = {
  SERVICE_TOS: "도담 서비스 이용에 필요한 기본 약관",
  CHILD_PERSONAL_INFO: "아동 프로필과 활동 기록을 안전하게 관리",
  DRAWING_ANALYSIS: "그림과 활동 과정을 관찰 자료로 정리",
  VOICE_PROCESSING: "음성 답변을 글자로 변환하고 대화에 활용",
  EXPERT_SHARING: "보호자가 지정한 전문가에게만 자료 공유",
  AI_TRAINING: "비식별 데이터를 서비스 개선에 활용",
  MARKETING: "서비스 소식과 이벤트 알림 수신",
};

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

  const termList = terms ?? [];
  const requiredUnmet = termList.some(
    (term) => term.required && !agreed[term.termId],
  );
  const allAgreed =
    termList.length > 0 && termList.every((term) => agreed[term.termId]);

  function setAllAgreed(value: boolean) {
    setError(null);
    if (!value) {
      setAgreed({});
      return;
    }
    const next: Record<number, boolean> = {};
    for (const term of termList) next[term.termId] = true;
    setAgreed(next);
  }

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
      const consents = termList.map((term) => ({
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

  const isConsent = step === "consent";

  return (
    <section className="onboarding-card">
      <p className="onboarding-progress">
        <span aria-hidden="true">●</span>
        <span>
          시작하기 {stepIndex + 1} / {steps.length}
        </span>
      </p>
      <h1 className="onboarding-title">{STEP_TITLE[step]}</h1>
      {isConsent ? (
        <p className="onboarding-subtitle">
          도담이 아이의 그림과 이야기를 안전하게 다룰 수 있도록 확인해 주세요.
        </p>
      ) : null}

      {step === "profile" ? (
        <div className="onboarding-fields">
          <div className="onboarding-roles">
            {ROLE_OPTIONS.map((option) => (
              <button
                key={option.value}
                type="button"
                className={`onboarding-role${role === option.value ? " is-selected" : ""}`}
                aria-pressed={role === option.value}
                onClick={() => setRole(option.value)}
              >
                <span className="onboarding-role-label">{option.label}</span>
                <span className="onboarding-role-desc">{option.description}</span>
              </button>
            ))}
          </div>
          <label className="onboarding-field">
            <span className="onboarding-field-label">닉네임</span>
            <input
              className="onboarding-input"
              value={nickname}
              onChange={(event) => setNickname(event.target.value)}
              maxLength={50}
              placeholder="커뮤니티에서 쓸 이름"
            />
          </label>
        </div>
      ) : null}

      {step === "email" ? (
        <label className="onboarding-field">
          <span className="onboarding-field-label">이메일</span>
          <input
            className="onboarding-input"
            type="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            maxLength={255}
            placeholder="you@example.com"
          />
          <span className="onboarding-field-hint">
            소셜 계정에서 이메일을 받지 못해 한 번만 확인이 필요해요.
          </span>
        </label>
      ) : null}

      {step === "consent" ? (
        <div className="onboarding-consent">
          {termsError ? (
            <p className="onboarding-error" role="alert">
              {termsError}
            </p>
          ) : null}
          {terms == null && termsError == null ? (
            <p className="onboarding-loading">약관을 불러오는 중…</p>
          ) : null}
          {terms != null ? (
            <>
              <div className="onboarding-consent-all">
                <label className="onboarding-consent-row">
                  <input
                    type="checkbox"
                    checked={allAgreed}
                    onChange={(event) => setAllAgreed(event.target.checked)}
                  />
                  <span className="onboarding-consent-text">
                    <span className="onboarding-consent-title">전체 동의하기</span>
                    <span className="onboarding-consent-desc">
                      필수와 선택 항목을 모두 동의해요.
                    </span>
                  </span>
                </label>
              </div>
              <div className="onboarding-consent-list">
                {termList.map((term) => (
                  <label key={term.termId} className="onboarding-consent-row">
                    <input
                      type="checkbox"
                      checked={agreed[term.termId] ?? false}
                      onChange={(event) =>
                        setAgreed((prev) => ({
                          ...prev,
                          [term.termId]: event.target.checked,
                        }))
                      }
                    />
                    <span className="onboarding-consent-text">
                      <span className="onboarding-consent-title">
                        {term.title}
                        {term.required ? (
                          <span className="onboarding-required">필수</span>
                        ) : null}
                      </span>
                      {CONSENT_DESCRIPTIONS[term.termCode] ? (
                        <span className="onboarding-consent-desc">
                          {CONSENT_DESCRIPTIONS[term.termCode]}
                        </span>
                      ) : null}
                    </span>
                    {term.contentUrl ? (
                      <a
                        className="onboarding-consent-chevron"
                        href={term.contentUrl}
                        target="_blank"
                        rel="noreferrer"
                        aria-label={`${term.title} 자세히 보기`}
                      >
                        ›
                      </a>
                    ) : null}
                  </label>
                ))}
              </div>
              <p className="onboarding-consent-note">
                선택 항목에 동의하지 않아도 도담을 이용할 수 있어요. 동의 내용은
                설정에서 언제든 변경할 수 있어요.
              </p>
            </>
          ) : null}
        </div>
      ) : null}

      {error ? (
        <p className="onboarding-error" role="alert">
          {error}
        </p>
      ) : null}

      <div className="onboarding-actions">
        {stepIndex > 0 ? (
          <button
            type="button"
            className="onboarding-button onboarding-button-ghost"
            onClick={() => setStepIndex((index) => Math.max(index - 1, 0))}
          >
            이전
          </button>
        ) : null}
        {isConsent ? (
          <button
            type="button"
            className="onboarding-button onboarding-button-primary"
            disabled={submitting || terms == null || requiredUnmet}
            onClick={submit}
          >
            {submitting ? "저장 중…" : "동의하고 시작하기"}
            <span aria-hidden="true">→</span>
          </button>
        ) : (
          <button
            type="button"
            className="onboarding-button onboarding-button-primary"
            onClick={goNext}
          >
            다음
          </button>
        )}
      </div>
    </section>
  );
}
