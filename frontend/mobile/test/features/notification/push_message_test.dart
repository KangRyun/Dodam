import 'package:dodam/features/notification/domain/entities/push_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> validData({
    String? relatedResourceType = 'REPORT',
    String? relatedResourceId = '55',
  }) => {
    'notificationId': '900',
    'type': 'ANALYSIS_COMPLETED',
    'title': '분석이 완료됐어요',
    'content': '리포트를 확인해 보세요',
    'relatedResourceType': ?relatedResourceType,
    'relatedResourceId': ?relatedResourceId,
  };

  test('계약대로 온 data 메시지를 파싱한다', () {
    final message = PushMessage.tryParse(validData())!;

    expect(message.notificationId, 900);
    expect(message.type, 'ANALYSIS_COMPLETED');
    expect(message.title, '분석이 완료됐어요');
    expect(message.content, '리포트를 확인해 보세요');
    expect(message.resourceType, PushResourceType.report);
    expect(message.resourceId, 55);
  });

  test('연결 자원이 없으면 자원 필드 없이 파싱한다', () {
    final message = PushMessage.tryParse(
      validData(relatedResourceType: null, relatedResourceId: null),
    )!;

    expect(message.resourceType, isNull);
    expect(message.resourceId, isNull);
  });

  test('자원 유형과 식별자가 쌍이 아니면 둘 다 버린다', () {
    // 한쪽만으로는 이동 대상을 정할 수 없어 라우팅이 불가능하다.
    final onlyType = PushMessage.tryParse(
      validData(relatedResourceId: null),
    )!;
    final onlyId = PushMessage.tryParse(
      validData(relatedResourceType: null),
    )!;

    expect(onlyType.resourceType, isNull);
    expect(onlyType.resourceId, isNull);
    expect(onlyId.resourceType, isNull);
    expect(onlyId.resourceId, isNull);
  });

  test('허용되지 않은 알림 유형은 폐기한다', () {
    final data = validData()..['type'] = 'UNKNOWN_TYPE';

    expect(PushMessage.tryParse(data), isNull);
  });

  test('필수 키가 빠지거나 공백이면 폐기한다', () {
    expect(PushMessage.tryParse(null), isNull);
    expect(PushMessage.tryParse(const {}), isNull);
    expect(PushMessage.tryParse(validData()..remove('notificationId')), isNull);
    expect(PushMessage.tryParse(validData()..remove('title')), isNull);
    expect(PushMessage.tryParse(validData()..['title'] = '   '), isNull);
  });

  test('숫자가 아닌 notificationId는 폐기한다', () {
    final data = validData()..['notificationId'] = 'not-a-number';

    expect(PushMessage.tryParse(data), isNull);
  });

  test('알 수 없는 자원 유형은 무시하고 본문은 살린다', () {
    final data = validData(relatedResourceType: 'CHILD');

    final message = PushMessage.tryParse(data)!;

    expect(message.resourceType, isNull);
    expect(message.notificationId, 900);
  });
}
