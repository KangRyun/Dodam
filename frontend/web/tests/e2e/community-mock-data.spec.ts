import { expect, test } from "@playwright/test";

import { MockCommunityRepository } from "@/features/community/community";

test("카테고리와 검색어로 커뮤니티 더미 데이터를 조회한다", async () => {
  const repository = new MockCommunityRepository();

  const expertFeed = await repository.getFeed({
    category: "EXPERT_COLUMN",
  });
  const searchedFeed = await repository.getFeed({ query: "검은색" });

  expect(expertFeed.posts).toHaveLength(1);
  expect(expertFeed.posts[0]?.category).toBe("EXPERT_COLUMN");
  expect(searchedFeed.posts).toHaveLength(1);
  expect(searchedFeed.posts[0]?.id).toBe(1001);
});

test("게시글 상세와 존재하지 않는 게시글을 구분한다", async () => {
  const repository = new MockCommunityRepository();

  const post = await repository.getPost(1001);
  const missingPost = await repository.getPost(9999);

  expect(post?.answerStatus).toBe("ANSWERED");
  expect(post?.comments).toHaveLength(2);
  expect(missingPost).toBeNull();
});

test("좋아요순 정렬은 좋아요 수가 많은 게시글부터 반환한다", async () => {
  const repository = new MockCommunityRepository();
  const feed = await repository.getFeed({ sort: "likeCount,desc" });

  const counts = feed.posts.map((post) => post.likeCount);
  expect(counts).toEqual([...counts].sort((left, right) => right - left));
});
