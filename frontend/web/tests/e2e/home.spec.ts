import { expect, test } from "@playwright/test";

test("기본 경로에서 커뮤니티 화면으로 진입한다", async ({ page }) => {
  await page.goto("/");

  await expect(
    page.getByRole("heading", { name: "마음그림 커뮤니티" }),
  ).toBeVisible();
  await expect(page).toHaveURL(/\/community$/);
  await expect(
    page.getByRole("searchbox", { name: "관심 있는 이야기 검색" }),
  ).toBeVisible();
});
