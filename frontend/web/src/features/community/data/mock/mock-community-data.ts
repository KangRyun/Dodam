import type {
  CommunityAuthor,
  CommunityFeed,
} from "@/features/community/domain/community-models";

const guardianAuthor: CommunityAuthor = {
  id: 101,
  nickname: "달빛토끼",
  role: "GUARDIAN",
  avatar: "🐰",
};

const expertAuthor: CommunityAuthor = {
  id: 201,
  nickname: "김하늘 미술치료사",
  role: "EXPERT",
  avatar: "👩‍⚕️",
  credential: "아동·가족상담센터 · 미술심리치료사",
};

const adminAuthor: CommunityAuthor = {
  id: 1,
  nickname: "운영팀",
  role: "ADMIN",
  avatar: "🌱",
};

// 화면 설계 검증을 위한 승인된 1차 MVP 데이터
export const mockCommunityFeed: CommunityFeed = {
  profile: {
    nickname: "민지엄마",
    avatar: "🌱",
    connectedProvider: "KAKAO",
  },
  popularTags: [
    "색채심리",
    "HTP",
    "분리불안",
    "유아미술",
    "감정표현",
    "등원거부",
  ],
  posts: [
    {
      id: 1001,
      category: "EXPERT_QNA",
      title: "아이가 검은색만 쓰려고 해요. 괜찮은 걸까요?",
      excerpt:
        "6살 아이인데 최근 한 달째 그림마다 검은 크레파스만 골라요. 억지로 다른 색을 권하는 게 맞을지 걱정돼요.",
      content:
        "6살 아이인데 최근 한 달째 그림을 그릴 때마다 검은 크레파스만 골라요. 처음엔 그냥 그러려니 했는데 이제는 조금 걱정이 돼요.\n\n억지로 다른 색을 권하는 게 맞을까요? 아니면 그냥 지켜보는 게 나을까요? 비슷한 경험 있으신 분들 조언 부탁드려요.",
      author: guardianAuthor,
      tags: ["색채심리", "유아미술"],
      isAnonymous: false,
      isLiked: false,
      likeCount: 24,
      commentCount: 12,
      viewCount: 342,
      createdAt: "2026-07-14T14:20:00+09:00",
      answerStatus: "ANSWERED",
      comments: [
        {
          id: 5001,
          author: expertAuthor,
          content:
            "특정 색만 고르는 시기는 발달 과정에서 흔히 나타날 수 있어요. 색 자체보다 그림을 그릴 때 아이의 표정과 이야기를 함께 살펴봐 주세요. 억지로 다른 색을 권하기보다 선택지를 자연스럽게 곁에 두는 것을 권합니다.",
          helpfulCount: 31,
          createdAt: "2026-07-14T15:20:00+09:00",
        },
        {
          id: 5002,
          author: {
            id: 102,
            nickname: "햇살맘",
            role: "GUARDIAN",
            avatar: "🌻",
          },
          content:
            "저희 아이도 비슷한 시기가 있었는데 지나고 나니 자연스럽게 다양한 색을 쓰더라고요.",
          helpfulCount: 0,
          createdAt: "2026-07-14T16:10:00+09:00",
        },
      ],
    },
    {
      id: 1002,
      category: "GUARDIAN_STORY",
      title: "비 오는 날 그리기 템플릿, 아이가 이야기를 많이 했어요",
      excerpt:
        "주말에 아이랑 같이 해봤는데 평소보다 이야기를 훨씬 많이 하더라고요. 짧게 후기 남겨봐요.",
      content:
        "주말에 비 오는 날 그리기 활동을 함께 해봤어요. 아이가 구름과 우산 이야기를 하면서 평소보다 자기 기분을 많이 표현해 줬어요.",
      author: {
        id: 103,
        nickname: "민지엄마",
        role: "GUARDIAN",
        avatar: "🌱",
      },
      tags: ["감정표현", "유아미술"],
      imageUrl: "/community/rainy-day-placeholder.png",
      isAnonymous: false,
      isLiked: true,
      likeCount: 18,
      commentCount: 5,
      viewCount: 126,
      createdAt: "2026-07-13T18:30:00+09:00",
      comments: [],
    },
    {
      id: 1003,
      category: "EXPERT_COLUMN",
      title: "연령별 크레파스 활동 가이드 (4–9세)",
      excerpt:
        "발달 단계에 따라 색과 도구 선택이 어떻게 달라지는지 정리했습니다. 가정에서 참고해보세요.",
      content:
        "아이의 연령과 손의 힘에 따라 편안하게 사용할 수 있는 크레파스의 굵기와 활동 방식이 달라질 수 있어요.",
      author: expertAuthor,
      tags: ["유아미술", "감정표현"],
      imageUrl: "/community/crayon-guide-placeholder.png",
      isAnonymous: false,
      isLiked: false,
      likeCount: 42,
      commentCount: 23,
      viewCount: 518,
      createdAt: "2026-07-11T10:00:00+09:00",
      comments: [],
    },
    {
      id: 1004,
      category: "NOTICE",
      title: "커뮤니티 이용 가이드라인 안내",
      excerpt:
        "AI 분석 결과와 대화 내용은 커뮤니티에 공개되지 않아요. 안전한 커뮤니티를 위해 꼭 확인해주세요.",
      content:
        "커뮤니티에는 아이의 이름, 학교, 위치와 같은 개인정보를 작성하지 말아 주세요. 그림을 공유할 때에도 분석 결과와 대화 내용은 공개되지 않습니다.",
      author: adminAuthor,
      tags: [],
      isAnonymous: false,
      isLiked: false,
      likeCount: 0,
      commentCount: 2,
      viewCount: 801,
      createdAt: "2026-07-10T09:00:00+09:00",
      comments: [],
    },
  ],
};
