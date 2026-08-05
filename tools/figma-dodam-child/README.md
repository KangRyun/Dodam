# Dodam Child UI v2 Generator

카카오키즈·Pinkfong·Khan Academy Kids·Toca Draw·Omy·Kids Doodle 레퍼런스의 선명한 활동 색상, 캐릭터 중심 탐색, 스케치북 감성을 도담에 맞게 새로 구성한 로컬 Figma Desktop 플러그인이다. 제품 코드와 보호자 화면은 수정하지 않는다.

Figma Starter 플랜의 파일당 3페이지 제한을 피하기 위해 네이티브 Figma 변수, 스타일, 컴포넌트, 모바일·태블릿 프레임을 한 페이지의 섹션으로 생성한다.

## 실행

1. Figma Desktop을 연다.
2. `Plugins → Development → Import plugin from manifest…`를 선택한다.
3. 이 폴더의 `manifest.json`을 선택한다.
4. `Plugins → Development → Dodam Child UI Generator`를 실행한다.
5. `v2 아동 화면 새로 만들기`를 누른다.

플러그인은 `Dodam Child UI v2 · All Screens` 한 페이지 안에 아래 섹션을 생성한다.

- `00 · V2 Direction`
- `01 · V2 Foundations`
- `02 · V2 Components`
- `10 · V2 Mobile`
- `11 · V2 Tablet`
- `99 · V2 Flow`

이전에 생성한 6페이지 구조가 있으면 한 페이지로 합치며, 그 외 원본 페이지와 레이어는 건드리지 않는다.

## 다시 빌드

```powershell
node tools/figma-dodam-child/build.mjs
```

`dist/code.js`에는 프로젝트의 노란 스카프 도다미 PNG 두 장이 Base64로 포함된다.
