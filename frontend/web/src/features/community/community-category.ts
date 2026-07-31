import type { CommunityPostCategory } from "@/features/community/domain/community-models";

/** 게시글 유형별 한국어 표시명. 백엔드 `PostType` 값과 1:1로 대응한다. */
export const categoryLabels: Record<CommunityPostCategory, string> = {
  GUARDIAN_STORY: "보호자 이야기",
  ACTIVITY_REVIEW: "활동 후기",
  EXPERT_COLUMN: "칼럼",
  ART_RESOURCE: "미술 활동 자료",
  DRAWING_GUIDE: "그림 활동 가이드",
  EXPERT_QNA: "전문가 Q&A",
  NOTICE: "공지",
};

/** 목록·썸네일에서 쓰는 유형별 아이콘. 없으면 기본 아이콘으로 대체한다. */
export const categoryIcons: Partial<Record<CommunityPostCategory, string>> = {
  GUARDIAN_STORY: "🌧️",
  ACTIVITY_REVIEW: "🖼️",
  EXPERT_COLUMN: "🖍️",
  ART_RESOURCE: "🎨",
  DRAWING_GUIDE: "📒",
};

/**
 * 작성 폼에서 보호자가 고를 수 있는 게시글 유형.
 *
 * `EXPERT_COLUMN`·`ART_RESOURCE`·`DRAWING_GUIDE`는 검증 전문가/관리자, `NOTICE`는
 * 관리자만 작성할 수 있어(명세 16.3) 일반 작성 폼 선택지에서 제외한다. 권한 밖 유형은
 * 백엔드가 403으로 최종 차단한다.
 */
export const writablePostCategories: readonly CommunityPostCategory[] = [
  "GUARDIAN_STORY",
  "ACTIVITY_REVIEW",
  "EXPERT_QNA",
];
