import { expect, test } from "@playwright/test";

// S15P11B209-769 — 루트는 더 이상 커뮤니티로 리다이렉트하지 않는다. 랜딩이 서빙되고,
// 커뮤니티는 CTA 로 진입한다. AI 한계 고지(가드레일 9절)는 랜딩의 필수 요소라 함께 단언한다.
test("루트에서 랜딩을 보고 CTA로 커뮤니티에 진입한다", async ({ page }) => {
  await page.goto("/");

  await expect(page).toHaveURL(/\/$/);
  await expect(
    page.getByRole("heading", { name: "아이의 마음을 그림으로 만나요" }),
  ).toBeVisible();
  await expect(page.getByText("진단이 아니라 관찰 참고 자료")).toBeVisible();
  await expect(page.getByRole("link", { name: "앱 다운로드" })).toHaveAttribute(
    "href",
    "/download/",
  );

  await page.getByRole("link", { name: "커뮤니티 둘러보기" }).click();

  await expect(page).toHaveURL(/\/community$/);
  await expect(
    page.getByRole("link", { name: "도담 커뮤니티 홈" }),
  ).toBeVisible();
});
