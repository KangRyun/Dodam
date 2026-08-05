# Confirm Color Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 팔레트의 HSV 조작과 최근 색상 탭은 미리보기만 갱신하고, 사용자가 `선택`을 눌렀을 때만 캔버스 도구 색상과 최근 색상 이력을 변경한다.

**Architecture:** `DrawingColorPalette`는 임시 HSV 값과 확인·취소 액션을 표시하는 프레젠테이션 위젯으로 유지한다. `DrawingScreen._openColorPalette`가 다이얼로그/바텀시트의 nullable `Color` 결과를 소유하고, 결과가 있을 때만 기존 `_setColor` 진입점을 한 번 호출해 도구 아이콘 포인트 컬러와 최근 색상 이력을 함께 갱신한다.

**Tech Stack:** Flutter, Dart, Material dialogs/bottom sheets, `flutter_test`

## Global Constraints

- 기존 크레용 캔버스 디자인, 빠른 색상 버튼, HTP 도구 제한은 변경하지 않는다.
- 최근 색상은 최대 10개와 중복 제거 규칙을 유지한다.
- HSV 평면·색조 막대·채널 슬라이더·최근 색상 탭은 팔레트 내부 미리보기만 즉시 갱신한다.
- `선택`은 현재 미리보기 색을 적용하고 팔레트를 닫는다.
- `닫기`, 태블릿 바깥 영역 탭, 모바일 시트 dismiss는 변경을 취소한다.
- 구현과 커밋은 Jira `S15P11B209-926` 범위에서만 진행한다.

---

## File Map

- `frontend/mobile/lib/features/drawing/presentation/widgets/drawing_color_palette.dart`: 확인·취소 액션을 노출하고 기존 색상 편집 UI 아래에 액션 행을 렌더링한다.
- `frontend/mobile/lib/features/activity/presentation/screens/activity_screens.dart`: 팔레트의 임시 색을 지역 상태로 관리하고 nullable route 결과가 확정된 경우에만 `_setColor`를 호출한다.
- `frontend/mobile/test/features/drawing/drawing_color_palette_test.dart`: 액션 버튼과 최근 색상 탭의 임시 선택 동작을 검증한다.
- `frontend/mobile/test/features/drawing/drawing_responsive_layout_test.dart`: 실제 모바일/태블릿 `DrawingScreen`에서 확정·취소 전후의 도구 색과 최근 색상 이력을 검증한다.

### Task 1: 팔레트 확인·취소 인터페이스

**Files:**
- Modify: `frontend/mobile/lib/features/drawing/presentation/widgets/drawing_color_palette.dart`
- Test: `frontend/mobile/test/features/drawing/drawing_color_palette_test.dart`

**Interfaces:**
- Consumes: `HSVColor value`, `ValueChanged<HSVColor> onChanged`, `List<Color> recentColors`
- Produces: `VoidCallback onCancel`, `VoidCallback onConfirm`, keys `drawing-color-cancel` and `drawing-color-confirm`

- [ ] **Step 1: Write the failing widget tests**

Add callbacks to the palette harness and verify both labeled actions invoke only their corresponding callback. Keep the recent-color test but rename it to state that a tap updates the draft preview; assert neither confirmation nor cancellation occurs from the tap alone.

```dart
testWidgets('exposes separate cancel and confirm actions', (tester) async {
  var cancelled = 0;
  var confirmed = 0;
  await _pumpPalette(
    tester,
    initial: initial,
    previous: previous,
    onCancel: () => cancelled++,
    onConfirm: () => confirmed++,
  );

  await tester.tap(find.byKey(const ValueKey('drawing-color-cancel')));
  await tester.tap(find.byKey(const ValueKey('drawing-color-confirm')));

  expect(cancelled, 1);
  expect(confirmed, 1);
});
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `flutter test test/features/drawing/drawing_color_palette_test.dart --reporter expanded`

Expected: compilation or finder failure because `DrawingColorPalette` does not expose/render the two actions.

- [ ] **Step 3: Add the minimal palette API and action row**

Add required callbacks:

```dart
final VoidCallback onCancel;
final VoidCallback onConfirm;
```

Render two accessible buttons beneath the preview row. Use the existing Material palette surface and spacing tokens; `닫기` is secondary and `선택` is primary. Assign stable keys `drawing-color-cancel` and `drawing-color-confirm`.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run: `flutter test test/features/drawing/drawing_color_palette_test.dart --reporter expanded`

Expected: all palette widget tests pass without overflow at 336 px and 480 px widths.

- [ ] **Step 5: Commit the independently testable palette API**

```powershell
git add frontend/mobile/lib/features/drawing/presentation/widgets/drawing_color_palette.dart frontend/mobile/test/features/drawing/drawing_color_palette_test.dart
git commit -m "feat(canvas): [S15P11B209-926] 팔레트 확정 액션을 추가한다"
```

### Task 2: 확정 시점에만 도구 색과 최근 이력 반영

**Files:**
- Modify: `frontend/mobile/lib/features/activity/presentation/screens/activity_screens.dart`
- Test: `frontend/mobile/test/features/drawing/drawing_responsive_layout_test.dart`

**Interfaces:**
- Consumes: Task 1의 `DrawingColorPalette.onCancel`과 `onConfirm`
- Produces: `showGeneralDialog<Color>` / `showModalBottomSheet<Color>`의 nullable 확정 색; null은 취소, `Color`는 확정

- [ ] **Step 1: Write failing integration tests against the real DrawingScreen**

For tablet, open the palette, tap a different point in the HSV plane, and read the draft from the real `DrawingColorPalette`. Assert the real `DrawingToolbar.toolState.color` remains the original color before confirmation. Tap `drawing-color-confirm`, assert the palette closes and the toolbar color equals the captured draft. Reopen and assert the confirmed color is the first recent color.

For mobile, change the draft then tap `drawing-color-cancel`; assert the sheet closes and the toolbar color and recent list remain unchanged. Add a tablet barrier-dismiss assertion with the same cancellation behavior.

```dart
final before = tester.widget<DrawingToolbar>(find.byType(DrawingToolbar));
final draft = tester
    .widget<DrawingColorPalette>(find.byType(DrawingColorPalette))
    .value
    .toColor();
expect(
  tester.widget<DrawingToolbar>(find.byType(DrawingToolbar)).toolState.color,
  before.toolState.color,
);
await tester.tap(find.byKey(const ValueKey('drawing-color-confirm')));
expect(
  tester.widget<DrawingToolbar>(find.byType(DrawingToolbar)).toolState.color,
  draft,
);
```

- [ ] **Step 2: Run the integration tests and verify RED**

Run: `flutter test test/features/drawing/drawing_responsive_layout_test.dart --reporter expanded`

Expected: the pre-confirm assertion fails because current `onChanged` calls `_setColor` during HSV interaction, and action keys are not wired to route results.

- [ ] **Step 3: Implement nullable route results and deferred apply**

Keep `value` and `previousColor` local to `_openColorPalette`. In palette callbacks, only mutate `value` through the local `StatefulBuilder`. Pop `null` for cancel and `value.toColor()` for confirm.

```dart
final selectedColor = deviceClass == DrawingCanvasDeviceClass.tablet
    ? await showGeneralDialog<Color>(...)
    : await showModalBottomSheet<Color>(...);

if (selectedColor != null && mounted) {
  _setColor(selectedColor);
}
```

Do not call `_setColor` from `DrawingColorPalette.onChanged`. Barrier and swipe dismissal naturally return null.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run: `flutter test test/features/drawing/drawing_color_palette_test.dart test/features/drawing/drawing_responsive_layout_test.dart --reporter expanded`

Expected: all tests pass; confirmed colors update once, cancelled drafts do not update the tool or recent colors.

- [ ] **Step 5: Commit the screen integration**

```powershell
git add frontend/mobile/lib/features/activity/presentation/screens/activity_screens.dart frontend/mobile/test/features/drawing/drawing_responsive_layout_test.dart
git commit -m "fix(canvas): [S15P11B209-926] 색상을 선택 후 반영한다"
```

### Task 3: Regression Verification

**Files:**
- Verify only; no production file changes expected

**Interfaces:**
- Consumes: Tasks 1-2 complete implementation
- Produces: analyzer and test evidence for handoff

- [ ] **Step 1: Run drawing regressions**

Run: `flutter test test/features/drawing --reporter compact`

Expected: all drawing tests pass, including responsive layouts, HTP constraints, toolbar accessibility, draft restore, and AI conversation lock.

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 3: Run the full mobile test suite**

Run: `flutter test --reporter compact`

Expected: the complete suite passes with no failures.

- [ ] **Step 4: Validate the patch and repository scope**

Run: `git diff --check origin/develop...HEAD`

Run: `git status --short --branch`

Run: `git log --oneline origin/develop..HEAD`

Expected: no whitespace errors; only the plan, palette widget, activity screen, and their focused tests differ from `origin/develop`; the worktree is clean after commits.
