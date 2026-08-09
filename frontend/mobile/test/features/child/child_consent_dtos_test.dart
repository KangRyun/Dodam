import 'package:dodam/features/child/data/dto/child_consent_dtos.dart';
import 'package:dodam/features/consent/domain/enums/consent_target_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CONSENT-01 응답 한 건을 필드 그대로 파싱한다', () {
    final term = ConsentTermDto.fromJson(<String, dynamic>{
      'termId': 1,
      'termCode': 'SERVICE_TOS',
      'targetScope': 'USER',
      'required': true,
      'version': 'v1',
      'title': '서비스 이용약관',
      'contentUrl': 'https://i15b209.p.ssafy.io/legal/terms/',
      'contentHtml': '<p>제1조(목적)</p>',
      'effectiveAt': '2020-01-01T00:00:00Z',
    });

    expect(term.termId, 1);
    expect(term.termCode, 'SERVICE_TOS');
    expect(term.title, '서비스 이용약관');
    expect(term.required, isTrue);
    expect(term.version, 'v1');
    expect(term.targetScope, ConsentTargetScope.user);
    expect(term.contentUrl, 'https://i15b209.p.ssafy.io/legal/terms/');
    expect(term.contentHtml, '<p>제1조(목적)</p>');
  });

  test('아동 대상 약관은 CHILD 범위로 매핑한다', () {
    // 이 매핑이 끊기면 약관 열람 화면에서 보호자·아동 구분이 통째로 사라진다.
    // 목록은 그대로 보이므로 화면 테스트로는 잡히지 않는다.
    final term = ConsentTermDto.fromJson(<String, dynamic>{
      'termId': 5,
      'termCode': 'VOICE_PROCESSING',
      'targetScope': 'CHILD',
      'required': false,
      'version': 'v1',
      'title': '음성 데이터 처리',
    });

    expect(term.targetScope, ConsentTargetScope.child);
    expect(term.required, isFalse);
  });

  test('앱이 모르는 targetScope는 예외 대신 null로 떨어뜨린다', () {
    // 서버가 범위를 늘려도 목록 조회가 통째로 실패하지 않아야 한다.
    // 범위를 모르는 약관은 화면에서 "기타" 묶음에 남는다.
    final unknown = ConsentTermDto.fromJson(<String, dynamic>{
      'termId': 9,
      'termCode': 'FUTURE_SCOPE',
      'targetScope': 'ORGANIZATION',
      'required': false,
      'version': 'v1',
      'title': '미래 약관',
    });
    final nonString = ConsentTermDto.fromJson(<String, dynamic>{
      'termId': 10,
      'termCode': 'WRAPPED_SCOPE',
      'targetScope': {'code': 'USER'},
      'required': false,
      'version': 'v1',
      'title': '객체로 감싼 범위',
    });

    expect(unknown.targetScope, isNull);
    expect(nonString.targetScope, isNull);
  });

  test('선택 필드가 빠진 응답도 기본값으로 파싱한다', () {
    final term = ConsentTermDto.fromJson(<String, dynamic>{
      'termId': 2,
      'termCode': 'MARKETING',
    });

    expect(term.termId, 2);
    // title이 없으면 termCode로 대신한다.
    expect(term.title, 'MARKETING');
    expect(term.required, isFalse);
    expect(term.version, '');
    expect(term.targetScope, isNull);
    expect(term.contentUrl, isNull);
    expect(term.contentHtml, isNull);
  });
}
