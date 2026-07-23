import { expect, test } from "@playwright/test";

test("웹 초기 화면을 표시한다", async ({ page }) => {
  await page.goto("/");

  await expect(
    page.getByRole("heading", { name: "웹 개발 환경 준비 완료" }),
  ).toBeVisible();
});
