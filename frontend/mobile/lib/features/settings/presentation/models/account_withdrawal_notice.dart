/// 데이터 처리 안내 항목의 성격. 화면은 이 값으로 아이콘과 색을 정한다.
enum AccountWithdrawalNoticeTone {
  /// 탈퇴로 삭제 처리되는 것.
  removed,

  /// 탈퇴해도 삭제되지 않고 남는 것.
  kept,

  /// 예약만 되고 탈퇴 시점에 끝나지 않는 것.
  scheduled,

  /// 계약이 아직 정하지 않아 안내할 수 없는 것.
  undecided,
}

/// 탈퇴 확인 화면에 표시하는 데이터 처리 안내 한 묶음.
final class AccountWithdrawalNoticeSection {
  const AccountWithdrawalNoticeSection({
    required this.tone,
    required this.title,
    required this.items,
  });

  final AccountWithdrawalNoticeTone tone;
  final String title;
  final List<String> items;
}

/// 명세 §6.4가 "탈퇴 응답 전 확인 화면에 표시한다"고 요구한 안내를 만든다.
///
/// 문구는 모두 서버가 실제로 하는 일에 맞춘다. 되돌릴 수 없는 동작이라, 계약
/// 문서보다 **커밋된 백엔드 코드**가 우선한다.
///
/// - 사용자 행 Soft Delete·전 기기 세션 폐기: `UserDeletionService.java:120-121`
/// - 소셜 인증 계정 물리 삭제와 그로 인한 재가입 가능: 같은 파일 `:117-119`,
///   `AuthAccountRepository.java:33-35`. 재로그인은 `OAuthAccountProvisioningService.java:64,69`가
///   `User.pending`을 새로 만들므로 **복구가 아니라 신규 가입**이다
/// - 단독 보호 아동 Soft Delete와 파일 삭제 예약: `ChildDeletionService.java:106-109`,
///   `ChildDeletionRepository.java:74-86,95-125`
/// - 단독 보호 아동의 그리기 획 데이터 물리 삭제: `StrokeBatchDeletionService.java:61-67`
///   → `StrokeBatchDocumentRepository.deleteByChildId`. Commit 직후 즉시·영구 삭제다
/// - 공동 보호 아동은 관계만 해제: `ChildDeletionRepository.java:165-168`
/// - 동의 기록 보존: 탈퇴 경로가 `consents`를 건드리지 않는다.
///   `UserDeletionService.java:37` javadoc, `docs/인프라/파일-수명주기-정책.md:20`
/// - 커뮤니티 글 잔존: `UserDeletionService`가 커뮤니티 테이블을 건드리지 않고
///   `User.markDeleted`(`User.java:187-191`)가 닉네임을 익명화하지 않는다.
///   목록·상세 Query(`CommunityPostListRepositoryImpl.java:24,46`)도 삭제 계정을
///   걸러내지 않아 닉네임이 그대로 노출된다
/// - 파일 물리 삭제 미보장: `storage_deletion_jobs`에 INSERT하는 생산자만 있고
///   소비 워커가 없다. `API_명세서_최종.md:446`도 범위 밖으로 규정한다
///
/// [connectedChildCount]는 현재 이 계정에 연결된 아이 수다. 어떤 아이가 단독
/// 보호인지 공동 보호인지는 서버만 알 수 있어(`ChildSummaryDto`에 보호자 수가
/// 없다) 개별 아이를 지목하지 않고 두 규칙을 함께 안내한다.
///
/// **`null`은 "아직 확인하지 못했다"는 뜻이다.** 목록 조회가 실패했을 때도 서버는
/// 조건 없이 단독 보호 아동을 삭제하므로(`UserDeletionService.java:115`), 확정되지
/// 않은 상태에서 "아이가 없다"고 단정하면 거짓 안심을 준다. 0이라고 확인한
/// 경우에만 없다고 말한다.
List<AccountWithdrawalNoticeSection> buildAccountWithdrawalNotice({
  required int? connectedChildCount,
}) {
  // 0으로 확정된 경우에만 "아이가 없다"고 말한다. null(미확정)이면 아동 규칙을
  // 모두 보여주는 쪽이 안전하다.
  final hasNoChildren = connectedChildCount == 0;
  final showChildRules = !hasNoChildren;

  return [
    AccountWithdrawalNoticeSection(
      tone: AccountWithdrawalNoticeTone.removed,
      title: '탈퇴하면 이렇게 처리돼요',
      items: [
        '계정이 삭제 상태로 바뀌어 지금 계정으로는 더 이상 로그인할 수 없어요.',
        '모든 기기의 로그인이 함께 해제돼요.',
        '소셜 로그인 연결은 서버에서 지워져요. 같은 소셜 계정으로 다시 가입할 수는 있지만, 이전 데이터를 되찾을 수는 없고 처음부터 새로 시작하는 계정이에요.',
        if (showChildRules)
          '회원님 혼자 돌보는 아이는 프로필이 삭제 상태로 바뀌고, 그 아이의 그림·대화 음성·리포트·프로필 이미지가 삭제 대상으로 등록돼요.',
        if (showChildRules)
          '회원님 혼자 돌보는 아이가 그림을 그린 과정(획) 기록은 되돌릴 수 없게 바로 지워져요.',
      ],
    ),
    AccountWithdrawalNoticeSection(
      tone: AccountWithdrawalNoticeTone.kept,
      title: '삭제되지 않고 남는 것도 있어요',
      items: [
        if (showChildRules)
          '다른 보호자와 함께 돌보는 아이는 삭제하지 않아요. 그 아이의 정보는 그대로 두고 회원님과의 보호자 연결만 해제돼요.',
        if (hasNoChildren) '지금은 연결된 아이가 없어서 함께 삭제될 아이 데이터도 없어요.',
        '회원 정보는 완전히 지우지 않고 삭제 상태로 표시해 서버에 남겨요.',
        '약관·개인정보 처리에 동의한 기록은 분쟁에 대비해 삭제하지 않고 보존해요.',
        '커뮤니티에 쓴 글과 댓글은 삭제되지 않아요. 글에는 작성자 닉네임도 그대로 남으니, 지우고 싶다면 탈퇴 전에 직접 삭제해 주세요.',
      ],
    ),
    const AccountWithdrawalNoticeSection(
      tone: AccountWithdrawalNoticeTone.scheduled,
      title: '탈퇴 즉시 끝나지 않는 것도 있어요',
      items: [
        '그림·음성·리포트 파일은 삭제 대상 목록에 올라가요. 실제로 저장소에서 지워지는 시점은 아직 보장해 드릴 수 없어요.',
        '탈퇴가 끝났다고 해서 파일이 이미 완전히 지워졌다는 뜻은 아니에요.',
      ],
    ),
    const AccountWithdrawalNoticeSection(
      tone: AccountWithdrawalNoticeTone.undecided,
      title: '아직 안내드릴 수 없는 것',
      items: [
        '보존하는 동의 기록을 언제까지 두는지, 어떻게 알아볼 수 없게 바꾸는지는 아직 정해지지 않았어요. 확정되면 이 화면에서 알려드릴게요.',
      ],
    ),
  ];
}
