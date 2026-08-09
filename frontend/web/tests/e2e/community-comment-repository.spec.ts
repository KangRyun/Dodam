import { expect, test } from "@playwright/test";

import { ApiCommunityRepository } from "@/features/community/community";

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

test.afterEach(() => {
  globalThis.fetch = originalFetch;
});

test("댓글 목록을 표시용 모델로 매핑하고 정렬 쿼리를 보낸다", async () => {
  const calls = installFetch({
    status: 200,
    body: {
      success: true,
      code: "COMMON_200",
      message: "ok",
      data: {
        content: [
          {
            commentId: 5001,
            postId: 1001,
            author: {
              userId: 201,
              nickname: "김하늘 미술치료사",
              role: "EXPERT",
              profileImageUrl: null,
            },
            anonymous: false,
            content: "특정 색만 고르는 시기는 흔합니다.",
            expertAnswer: true,
            accepted: false,
            editableByMe: false,
            createdAt: "2026-07-14T15:20:00Z",
            updatedAt: "2026-07-14T15:20:00Z",
          },
        ],
        page: 0,
        size: 100,
        totalElements: 1,
        totalPages: 1,
        first: true,
        last: true,
        hasNext: false,
      },
    },
  });

  const comments = await new ApiCommunityRepository().getComments(1001);

  expect(calls[0]?.url).toContain("/posts/1001/comments");
  expect(calls[0]?.url).toContain("sort=createdAt,asc");
  expect(comments).toHaveLength(1);
  expect(comments[0]?.isExpertAnswer).toBe(true);
  expect(comments[0]?.author.role).toBe("EXPERT");
});

test("댓글 작성은 content·anonymous를 전송하고 생성된 댓글을 매핑한다", async () => {
  const calls = installFetch({
    status: 201,
    body: {
      success: true,
      code: "COMMON_201",
      message: "created",
      data: {
        commentId: 6001,
        postId: 1001,
        author: null,
        anonymous: true,
        content: "익명 댓글이에요.",
        expertAnswer: false,
        accepted: false,
        editableByMe: true,
        createdAt: "2026-07-31T00:00:00Z",
        updatedAt: "2026-07-31T00:00:00Z",
      },
    },
  });

  const created = await new ApiCommunityRepository().createComment(1001, {
    content: "익명 댓글이에요.",
    anonymous: true,
  });

  expect(calls[0]?.init?.method).toBe("POST");
  expect(String(calls[0]?.init?.body)).toContain("\"anonymous\":true");
  expect(created.id).toBe(6001);
  expect(created.editableByMe).toBe(true);
  expect(created.author.nickname).toBe("익명 보호자");
});

test("댓글 삭제는 DELETE /comments/{id}를 호출한다", async () => {
  const calls = installFetch({ status: 204, body: null });

  await new ApiCommunityRepository().deleteComment(6001);

  expect(calls[0]?.url).toContain("/comments/6001");
  expect(calls[0]?.init?.method).toBe("DELETE");
});
