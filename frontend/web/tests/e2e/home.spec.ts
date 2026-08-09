import { expect, test } from "@playwright/test";

// S15P11B209-769 — 루트는 더 이상 커뮤니티로 리다이렉트하지 않는다. 랜딩이 서빙되고,
// 커뮤니티는 CTA 로 진입한다. AI 한계 고지(가드레일 9절)는 랜딩의 필수 요소라 함께 단언한다.
// S15P11B209-880 — 랜딩 화면을 크레용 디자인으로 교체했다. 제목·고지 문구만 새 디자인에
// 맞추고, 루트 계약(다운로드·커뮤니티·비진단 고지·약관)은 그대로 단언한다.
test("루트에서 랜딩을 보고 CTA로 커뮤니티에 진입한다", async ({ page }) => {
  await page.goto("/");

  await expect(page).toHaveURL(/\/$/);
  await expect(
    page.getByRole("heading", { name: /아이의 그림과 이야기를/ }),
  ).toBeVisible();

  // 비진단 고지는 활동 기록 섹션과 약속 노트 두 곳에 각각 남아 있어야 한다.
  // 앞은 의료적·심리적 진단이 아님을, 뒤는 AI 의 역할 한계를 명시한다.
  await expect(
    page.getByText("의료적·심리적 진단이 아닌", { exact: false }),
  ).toBeVisible();
  await expect(
    page.getByText("아이를 진단하거나 평가하지 않아요", { exact: false }),
  ).toBeVisible();

  await expect(page.getByRole("link", { name: "앱 다운로드" })).toHaveAttribute(
    "href",
    "/download/",
  );
  await expect(
    page.getByRole("link", { name: "개인정보처리방침" }),
  ).toHaveAttribute("href", "/legal/privacy/");
  await expect(page.getByRole("link", { name: "이용약관" })).toHaveAttribute(
    "href",
    "/legal/terms/",
  );

  await page.getByRole("link", { name: "커뮤니티 둘러보기" }).click();

  await expect(page).toHaveURL(/\/community$/);
  await expect(
    page.getByRole("link", { name: "도담 커뮤니티 홈" }),
  ).toBeVisible();
});

// 랜딩 CSS 는 루트 page 가 import 하므로 한 번 로드되면 client 이동 뒤에도 문서에 남는다.
// 전역 selector 를 두면 커뮤니티까지 오염되므로, 랜딩을 거쳐 이동해도 body 배경이
// 랜딩 아이보리(#fff9ef)로 바뀌지 않는지 확인한다(S15P11B209-880).
test("랜딩을 거쳐 커뮤니티로 이동해도 랜딩 CSS가 전역으로 새지 않는다", async ({
  page,
}) => {
  await page.goto("/");
  await expect(page.locator(".landing")).toHaveCount(1);

  await page.getByRole("link", { name: "커뮤니티 둘러보기" }).click();
  await expect(page).toHaveURL(/\/community$/);

  // 랜딩 wrapper 자체가 커뮤니티에 남아 있으면 안 된다.
  await expect(page.locator(".landing")).toHaveCount(0);

  const bodyBackground = await page.evaluate(
    () => getComputedStyle(document.body).backgroundColor,
  );
  expect(bodyBackground).not.toBe("rgb(255, 249, 239)");
});

// 약속 노트는 tablist/tab/tabpanel 계약과 방향키 이동을 유지해야 한다(S15P11B209-880).
test("약속 노트는 방향키로 원칙을 넘긴다", async ({ page }) => {
  await page.goto("/");

  const tabs = page.getByRole("tab");
  await expect(tabs).toHaveCount(3);

  const first = tabs.nth(0);
  const second = tabs.nth(1);
  await expect(first).toHaveAttribute("aria-selected", "true");

  await first.focus();
  await page.keyboard.press("ArrowDown");

  await expect(second).toHaveAttribute("aria-selected", "true");
  await expect(first).toHaveAttribute("aria-selected", "false");
  await expect(second).toBeFocused();
  await expect(page.getByRole("tabpanel")).toHaveCount(1);
});
