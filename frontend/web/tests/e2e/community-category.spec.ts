import { expect, test } from "@playwright/test";

import { parseCommunityCategory } from "@/features/community/components/community-category-tabs";

test("지원하는 커뮤니티 카테고리만 선택 상태로 변환한다", () => {
  expect(parseCommunityCategory("EXPERT_QNA")).toBe("EXPERT_QNA");
  expect(parseCommunityCategory("UNKNOWN")).toBeUndefined();
  expect(parseCommunityCategory()).toBeUndefined();
});
