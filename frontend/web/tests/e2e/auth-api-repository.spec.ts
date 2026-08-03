import { expect, test } from "@playwright/test";

import { ApiAuthRepository } from "@/features/auth/data/api/api-auth-repository";

type FetchStub = { status: number; body: unknown };

const originalFetch = globalThis.fetch;

function installFetch(stub: FetchStub) {
  const calls: { url: string; init?: RequestInit }[] = [];
  globalThis.fetch = (async (url: string, init?: RequestInit) => {
    calls.push({ url: String(url), init });
    return {
      ok: stub.status >= 200 && stub.status < 300,
      status: stub.status,
      text: async () => (stub.body === null ? "" : JSON.stringify(stub.body)),
    } as Response;
  }) as typeof globalThis.fetch;
  return calls;
}

function parseBody(init?: RequestInit): Record<string, unknown> {
  return JSON.parse(String(init?.body ?? "{}")) as Record<string, unknown>;
}

test.afterEach(() => {
  globalThis.fetch = originalFetch;
});

test("약관 목록을 targetScope=USER로 조회하고 도메인 모델로 매핑한다", async () => {
  const calls = installFetch({
    status: 200,
    body: {
      success: true,
      code: "COMMON_200",
      message: "ok",
      data: [
        {
          termId: 7,
          termCode: "SERVICE",
          targetScope: "USER",
          required: true,
          version: "1.0",
          title: "서비스 이용약관",
          contentUrl: "https://example.com/terms",
          contentHtml: null,
          effectiveAt: "2026-01-01T00:00:00Z",
        },
      ],
    },
  });

  const terms = await new ApiAuthRepository().getTerms();

  expect(calls[0]?.url).toContain("consents/terms?targetScope=USER");
  expect(terms).toHaveLength(1);
  expect(terms[0]).toMatchObject({ termId: 7, required: true, termCode: "SERVICE" });
});

test("온보딩을 PUT /users/me/onboarding으로 저장한다", async () => {
  const calls = installFetch({
    status: 200,
    body: {
      success: true,
      code: "COMMON_200",
      message: "ok",
      data: {
        userId: 1,
        role: "GUARDIAN",
        nickname: "달빛토끼",
        email: "rabbit@example.com",
        accountStatus: "ACTIVE",
        onboardingCompleted: true,
      },
    },
  });

  const user = await new ApiAuthRepository().completeOnboarding({
    role: "GUARDIAN",
    nickname: "달빛토끼",
    email: "rabbit@example.com",
    consents: [{ termId: 7, action: "AGREE" }],
  });

  expect(calls[0]?.url).toContain("users/me/onboarding");
  expect(calls[0]?.init?.method).toBe("PUT");
  const body = parseBody(calls[0]?.init);
  expect(body).toMatchObject({
    role: "GUARDIAN",
    nickname: "달빛토끼",
    email: "rabbit@example.com",
    profileImageFileId: null,
    consents: [{ termId: 7, action: "AGREE" }],
  });
  expect(user).toMatchObject({ userId: 1, onboardingCompleted: true });
});

test("재발급을 POST /auth/reissue로 호출하고 세션으로 매핑한다", async () => {
  const calls = installFetch({
    status: 200,
    body: {
      success: true,
      code: "COMMON_200",
      message: "ok",
      data: {
        grantType: "Bearer",
        accessToken: "new-access",
        accessTokenExpiresInSeconds: 3600,
        refreshToken: "new-refresh",
        refreshTokenExpiresInSeconds: 1209600,
        user: {
          userId: 1,
          role: "GUARDIAN",
          nickname: "달빛토끼",
          email: "rabbit@example.com",
          emailRequired: false,
          accountStatus: "ACTIVE",
          onboardingCompleted: true,
        },
      },
    },
  });

  const session = await new ApiAuthRepository().reissue({
    refreshToken: "old-refresh",
    deviceId: "device-1",
  });

  expect(calls[0]?.url).toContain("auth/reissue");
  expect(calls[0]?.init?.method).toBe("POST");
  expect(parseBody(calls[0]?.init)).toMatchObject({
    refreshToken: "old-refresh",
    deviceId: "device-1",
  });
  expect(session.accessToken).toBe("new-access");
  expect(session.refreshToken).toBe("new-refresh");
  expect(session.user.emailRequired).toBe(false);
});

test("로그아웃을 POST /auth/logout으로 호출한다", async () => {
  const calls = installFetch({ status: 204, body: null });

  await new ApiAuthRepository().logout({
    refreshToken: "old-refresh",
    deviceId: "device-1",
  });

  expect(calls[0]?.url).toContain("auth/logout");
  expect(calls[0]?.init?.method).toBe("POST");
  expect(parseBody(calls[0]?.init)).toMatchObject({
    refreshToken: "old-refresh",
    deviceId: "device-1",
  });
});
