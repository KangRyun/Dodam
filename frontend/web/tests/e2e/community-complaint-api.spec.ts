import { expect, test } from "@playwright/test";

import { createCommunityComplaint } from "@/features/community/data/api/community-complaint-api";

const originalFetch = globalThis.fetch;

test.afterEach(() => {
  globalThis.fetch = originalFetch;
});

test("게시글 신고를 공통 신고 API 계약으로 제출한다", async () => {
  const calls: { url: string; init?: RequestInit }[] = [];
  globalThis.fetch = (async (url: string, init?: RequestInit) => {
    calls.push({ url: String(url), init });
    return {
      ok: true,
      status: 201,
      text: async () =>
        JSON.stringify({
          success: true,
          code: "COMMON_201",
          message: "created",
          data: { complaintId: 1 },
        }),
    } as Response;
  }) as typeof globalThis.fetch;

  await createCommunityComplaint({
    targetType: "POST",
    targetId: 10,
    reasonCode: "PERSONAL_INFORMATION",
    description: "개인정보가 포함되어 있습니다.",
  });

  expect(calls).toHaveLength(1);
  expect(calls[0]?.url.endsWith("/api/v1/complaints")).toBe(true);
  expect(calls[0]?.init?.method).toBe("POST");
  expect(JSON.parse(String(calls[0]?.init?.body))).toEqual({
    targetType: "POST",
    targetId: 10,
    reasonCode: "PERSONAL_INFORMATION",
    description: "개인정보가 포함되어 있습니다.",
  });
});

test("댓글 신고도 같은 API에 댓글 대상을 전달한다", async () => {
  const calls: { url: string; init?: RequestInit }[] = [];
  globalThis.fetch = (async (url: string, init?: RequestInit) => {
    calls.push({ url: String(url), init });
    return {
      ok: true,
      status: 201,
      text: async () => "",
    } as Response;
  }) as typeof globalThis.fetch;

  await createCommunityComplaint({
    targetType: "COMMENT",
    targetId: 44,
    reasonCode: "HARASSMENT",
  });

  expect(JSON.parse(String(calls[0]?.init?.body))).toEqual({
    targetType: "COMMENT",
    targetId: 44,
    reasonCode: "HARASSMENT",
  });
});
