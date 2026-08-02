import 'package:dodam/features/settings/presentation/models/account_withdrawal_notice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<String> itemsOf(
    List<AccountWithdrawalNoticeSection> sections,
    AccountWithdrawalNoticeTone tone,
  ) => sections
      .where((section) => section.tone == tone)
      .expand((section) => section.items)
      .toList();

  List<String> allItems(List<AccountWithdrawalNoticeSection> sections) =>
      sections.expand((section) => section.items).toList();

  group('아동 수가 확정되지 않은 경우', () {
    // 목록 조회 실패·미조회를 0으로 뭉개면, 서버는 조건 없이 단독 보호 아동을
    // 삭제하는데(UserDeletionService:115) 화면은 "삭제될 아이 데이터가 없다"고
    // 안내한다. 되돌릴 수 없는 동작 앞의 거짓 안심이라 가장 위험하다.
    test('"연결된 아이가 없다"고 단정하지 않는다', () {
      final items = allItems(
        buildAccountWithdrawalNotice(connectedChildCount: null),
      );

      expect(
        items.where((item) => item.contains('연결된 아이가 없어서')),
        isEmpty,
      );
    });

    test('단독 보호·공동 보호 아동 규칙을 모두 보여준다', () {
      final sections = buildAccountWithdrawalNotice(connectedChildCount: null);

      expect(
        itemsOf(sections, AccountWithdrawalNoticeTone.removed).where(
          (item) => item.contains('혼자 돌보는 아이는 프로필이 삭제 상태로'),
        ),
        hasLength(1),
      );
      expect(
        itemsOf(sections, AccountWithdrawalNoticeTone.kept).where(
          (item) => item.contains('다른 보호자와 함께 돌보는 아이는'),
        ),
        hasLength(1),
      );
    });
  });

  group('아동 수가 0으로 확정된 경우', () {
    test('아이가 없다고 안내하고 아동 규칙을 감춘다', () {
      final sections = buildAccountWithdrawalNotice(connectedChildCount: 0);
      final items = allItems(sections);

      expect(items.where((item) => item.contains('연결된 아이가 없어서')), hasLength(1));
      expect(items.where((item) => item.contains('혼자 돌보는 아이')), isEmpty);
      expect(items.where((item) => item.contains('다른 보호자와 함께 돌보는 아이')), isEmpty);
    });
  });

  group('물리 삭제되는 항목을 빠짐없이 알린다', () {
    // StrokeBatchDeletionService:61-67 → deleteByChildId. Commit 직후 즉시·영구
    // 삭제이며 실패는 로그로 삼켜진다. 단독 보호 아동에 한해 일어난다.
    test('그리기 획 기록이 즉시 지워진다는 사실을 삭제 항목에 넣는다', () {
      final removed = itemsOf(
        buildAccountWithdrawalNotice(connectedChildCount: 2),
        AccountWithdrawalNoticeTone.removed,
      );

      expect(
        removed.where(
          (item) =>
              item.contains('과정(획) 기록') && item.contains('되돌릴 수 없게 바로 지워져요'),
        ),
        hasLength(1),
      );
    });

    // AuthAccountRepository:33-35 물리 삭제 →
    // OAuthAccountProvisioningService:64,69가 재로그인 시 새 User.pending 생성.
    test('소셜 연결 삭제와 재가입이 "복구"가 아님을 함께 알린다', () {
      final removed = itemsOf(
        buildAccountWithdrawalNotice(connectedChildCount: 2),
        AccountWithdrawalNoticeTone.removed,
      );
      final rejoin = removed.singleWhere(
        (item) => item.contains('소셜 로그인 연결은 서버에서 지워져요'),
      );

      expect(rejoin, contains('같은 소셜 계정으로 다시 가입할 수는 있지만'));
      expect(rejoin, contains('이전 데이터를 되찾을 수는 없고'));
    });

    // users 행만 Soft Delete다. "계정 기록 자체"라고 넓게 쓰면 아무것도 안
    // 지워진다고 읽힌다.
    test('남는다고 말하는 대상을 회원 정보로 한정한다', () {
      final kept = itemsOf(
        buildAccountWithdrawalNotice(connectedChildCount: 2),
        AccountWithdrawalNoticeTone.kept,
      );

      expect(
        kept.where((item) => item.contains('회원 정보는 완전히 지우지 않고')),
        hasLength(1),
      );
      expect(kept.where((item) => item.contains('계정 기록 자체는')), isEmpty);
    });
  });

  group('남는 데이터', () {
    // 탈퇴 경로가 consents를 건드리지 않는다. 명세 §6.4는 법적 보존 데이터를
    // 확인 화면에 표시하라고 요구한다.
    test('동의 기록 보존은 확정 사실로 안내한다', () {
      final sections = buildAccountWithdrawalNotice(connectedChildCount: 0);

      expect(
        itemsOf(sections, AccountWithdrawalNoticeTone.kept).where(
          (item) => item.contains('동의한 기록은 분쟁에 대비해 삭제하지 않고 보존해요'),
        ),
        hasLength(1),
      );
      expect(
        itemsOf(sections, AccountWithdrawalNoticeTone.undecided).where(
          (item) => item.contains('법령에 따라 보존해야 하는 항목'),
        ),
        isEmpty,
        reason: '항목은 확정됐으므로 미정 칸에 두면 안 된다',
      );
    });

    test('아직 정해지지 않은 것은 보존 기간과 비식별화 방식뿐이다', () {
      final undecided = itemsOf(
        buildAccountWithdrawalNotice(connectedChildCount: 0),
        AccountWithdrawalNoticeTone.undecided,
      );

      expect(undecided, hasLength(1));
      expect(undecided.single, contains('언제까지 두는지'));
      expect(undecided.single, contains('알아볼 수 없게 바꾸는지'));
    });

    // User.markDeleted(User.java:187-191)는 닉네임을 익명화하지 않고, 커뮤니티
    // 목록 Query(CommunityPostListRepositoryImpl:24,46)는 삭제 계정을 거르지 않는다.
    test('커뮤니티 글·댓글 잔존과 탈퇴 전 직접 삭제를 안내한다', () {
      final kept = itemsOf(
        buildAccountWithdrawalNotice(connectedChildCount: 0),
        AccountWithdrawalNoticeTone.kept,
      );
      final community = kept.singleWhere(
        (item) => item.contains('커뮤니티에 쓴 글과 댓글'),
      );

      expect(community, contains('작성자 닉네임도 그대로 남으니'));
      expect(community, contains('탈퇴 전에 직접 삭제해 주세요'));
    });
  });

  // storage_deletion_jobs 소비 워커가 main 코드에 없다(생산 INSERT 4곳, 소비 0).
  // 삭제가 "진행된다"고 단정할 근거가 없으므로 등록까지만 보증한다.
  test('파일 물리 삭제는 시점을 보장하지 않는다고만 말한다', () {
    final scheduled = itemsOf(
      buildAccountWithdrawalNotice(connectedChildCount: 2),
      AccountWithdrawalNoticeTone.scheduled,
    );

    expect(
      scheduled.where((item) => item.contains('별도 처리로 진행돼요')),
      isEmpty,
      reason: '실행 주체가 없는데 진행된다고 단정하면 안 된다',
    );
    expect(
      scheduled.where((item) => item.contains('아직 보장해 드릴 수 없어요')),
      hasLength(1),
    );
    expect(
      scheduled.where((item) => item.contains('이미 완전히 지워졌다는 뜻은 아니에요')),
      hasLength(1),
    );
  });
}
