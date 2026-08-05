/**
 * 루트 랜딩(`/`) 공통 상수(S15P11B209-880).
 *
 * 링크 계약은 S15P11B209-769에서 확립된 루트 계약을 그대로 잇는다.
 * `/download/`·`/legal/*` 는 Next 라우터 밖의 nginx 정적 페이지라 next/link 를 쓰지 않는다.
 * `/community` 만 Next 내부 route 이므로 next/link 로 이동한다.
 * 로그인 전용 route 는 연결하지 않는다.
 */
export const DOWNLOAD_HREF = "/download/";
export const COMMUNITY_HREF = "/community";
export const FLOW_HREF = "#flow";

export const LEGAL_LINKS: ReadonlyArray<{ href: string; label: string }> = [
  { href: "/legal/privacy/", label: "개인정보처리방침" },
  { href: "/legal/terms/", label: "이용약관" },
];

export const NAV_ITEMS: ReadonlyArray<{ href: string; label: string }> = [
  { href: "#about", label: "도담 소개" },
  { href: FLOW_HREF, label: "이용 방법" },
  { href: "#report", label: "그림 활동 기록" },
  { href: COMMUNITY_HREF, label: "커뮤니티" },
];

/**
 * 로그인 화면과 공유하는 아이 손그림 asset.
 *
 * `/characters/*` 는 로그인 브랜드 패널이 쓰는 기존 원본이다. 같은 파일을 랜딩
 * 히어로에서도 참조해 중복 사본을 만들지 않는다(S15P11B209-880).
 */
export const DOODLE = {
  dino: "/characters/doodle_dino.png",
  tree: "/characters/doodle_tree.png",
  sun: "/characters/doodle_sun.png",
} as const;

const BASE = "/assets/landing/characters";

/** 랜딩 이미지 자산 경로 */
export const CHAR = {
  child: `${BASE}/child.png`,
  pyeonan: `${BASE}/pyeonan.png`,
  guide: `${BASE}/guide.png`,
  report: `${BASE}/report.png`,
  group: `${BASE}/group.png`,
  prince: `${BASE}/prince.png`,
  princess: `${BASE}/princess.png`,
  trumpeter: `${BASE}/trumpeter.png`,
  guardian: `${BASE}/guardian.png`,
  valDraw: `${BASE}/val_draw.png`,
  valTalk: `${BASE}/val_talk.png`,
  valRecord: `${BASE}/val_record.png`,
  icPencil: `${BASE}/ic_pencil_w.png`,
  icSpeech: `${BASE}/ic_speech.png`,
  icClipboard: `${BASE}/ic_clipboard.png`,
  repPalette: `${BASE}/rep_palette.png`,
  repPencil: `${BASE}/rep_pencil.png`,
  repSpeech: `${BASE}/rep_speech.png`,
  repNotebook: `${BASE}/rep_notebook.png`,
} as const;

/**
 * 도담이 곁의 문구류 친구들(S15P11B209-880 2차).
 *
 * 모두 1254×1254 정사각 RGBA 원본이고 아래 투명 여백이 17~19%로 비슷하다.
 * 같은 정사각 박스에 `object-fit: contain` 으로 담으면 비율을 왜곡하지 않고도
 * 시각 크기와 바닥선이 맞는다.
 */
export const FRIEND = {
  crayon: `${BASE}/crayon_friend.png`,
  sketchbook: `${BASE}/sketchbook_friend.png`,
  eraser: `${BASE}/eraser_friend.png`,
} as const;
