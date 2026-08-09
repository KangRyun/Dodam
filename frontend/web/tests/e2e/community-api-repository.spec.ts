import { expect, test } from "@playwright/test";

import { ApiCommunityRepository } from "@/features/community/community";

type FetchStub = {
  status: number;
  body: unknown;
};

const originalFetch = globalThis.fetch;

/** 지정한 응답을 돌려주는 fetch 스텁을 설치하고 마지막 요청을 기록한다. */
function installFetch(stub: FetchStub) {
  const calls: { url: string; init?: RequestInit }[] = [];
  globalThis.fetch = (async (url: string, init?: RequestInit) => {
    calls.push({ url: String(url), init });
    return {
      ok: stub.status >= 200 && stub.status < 300,
      status: stub.status,
      text: async () =>
        stub.body === null ? "" : JSON.stringify(stub.body),
    } as Response;
  }) as typeof globalThis.fetch;
  return calls;
}

test.afterEach(() => {
  globalThis.fetch = originalFetch;
});

test("목록 응답을 표시용 게시글로 매핑하고 필터를 쿼리로 보낸다", async () => {
  const calls = installFetch({
    status: 200,
    body: {
      success: true,
      code: "COMMON_200",
      message: "ok",
      data: {
        content: [
          {
            postId: 10,
            postType: "GUARDIAN_STORY",
            title: "제목",
            previewContent: "미리보기",
            author: { userId: 5, nickname: "달빛토끼" },
            anonymous: false,
            likeCount: 3,
            commentCount: 1,
            likedByMe: true,
            createdAt: "2026-07-20T00:00:00Z",
            updatedAt: "2026-07-20T00:00:00Z",
          },
        ],
        page: 0,
        size: 20,
        totalElements: 1,
        totalPages: 1,
        first: true,
        last: true,
        hasNext: false,
      },
    },
  });

  const repository = new ApiCommunityRepository();
  const feed = await repository.getFeed({
    category: "GUARDIAN_STORY",
    query: "토끼",
    sort: "likeCount,desc",
  });

  expect(calls[0]?.url).toContain("/posts?");
  expect(calls[0]?.url).toContain("type=GUARDIAN_STORY");
  expect(calls[0]?.url).toContain("keyword=");
  expect(calls[0]?.url).toContain("sort=likeCount%2Cdesc");
  expect(feed.posts).toHaveLength(1);
  expect(feed.posts[0]?.excerpt).toBe("미리보기");
  expect(feed.posts[0]?.isLiked).toBe(true);
  expect(feed.posts[0]?.author.nickname).toBe("달빛토끼");
});

test("익명 게시글 상세는 작성자를 마스킹하고 수정 가능 여부를 전달한다", async () => {
  installFetch({
    status: 200,
    body: {
      success: true,
      code: "COMMON_200",
      message: "ok",
      data: {
        postId: 11,
        postType: "EXPERT_QNA",
        title: "익명 질문",
        content: "본문 내용",
        author: null,
        anonymous: true,
        attachments: [],
        templateData: [],
        likeCount: 0,
        commentCount: 0,
        likedByMe: false,
        editableByMe: true,
        createdAt: "2026-07-21T00:00:00Z",
        updatedAt: "2026-07-21T00:00:00Z",
      },
    },
  });

  const repository = new ApiCommunityRepository();
  const post = await repository.getPost(11);

  expect(post?.content).toBe("본문 내용");
  expect(post?.isAnonymous).toBe(true);
  expect(post?.editableByMe).toBe(true);
});

test("존재하지 않는 게시글은 null을 반환한다", async () => {
  installFetch({
    status: 404,
    body: {
      success: false,
      code: "POST_NOT_FOUND",
      message: "게시글을 찾을 수 없습니다.",
      data: null,
    },
  });

  const repository = new ApiCommunityRepository();
  const post = await repository.getPost(9999);

  expect(post).toBeNull();
});

test("좋아요 등록은 COMM-06 경로로 요청하고 결과를 반환한다", async () => {
  const calls = installFetch({
    status: 201,
    body: {
      success: true,
      code: "COMMON_201",
      message: "ok",
      data: { postId: 12, liked: true, likeCount: 4 },
    },
  });

  const repository = new ApiCommunityRepository();
  const result = await repository.likePost(12);

  expect(calls[0]?.url).toContain("/posts/12/likes");
  expect(calls[0]?.init?.method).toBe("POST");
  expect(result).toEqual({ postId: 12, liked: true, likeCount: 4 });
});

test("좋아요 취소는 COMM-07 경로로 DELETE 요청한다", async () => {
  const calls = installFetch({ status: 204, body: null });

  const repository = new ApiCommunityRepository();
  await repository.unlikePost(12);

  expect(calls[0]?.url).toContain("/posts/12/likes");
  expect(calls[0]?.init?.method).toBe("DELETE");
});
