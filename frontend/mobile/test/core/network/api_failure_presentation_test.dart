import 'package:dodam/core/network/network.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiFailurePresentation.of — 전송 실패', () {
    test('연결 실패는 오프라인으로 분류하고 재시도를 허용한다', () {
      final presentation = ApiFailurePresentation.of(
        const ApiTransportFailure(type: ApiTransportFailureType.connection),
      );

      expect(presentation.kind, ApiFailureKind.offline);
      expect(presentation.isConnectivity, isTrue);
      expect(presentation.canRetry, isTrue);
      expect(presentation.message, contains('인터넷 연결'));
    });

    test('네 가지 타임아웃을 모두 timeout으로 모은다', () {
      const timeouts = [
        ApiTransportFailureType.connectionTimeout,
        ApiTransportFailureType.sendTimeout,
        ApiTransportFailureType.receiveTimeout,
        ApiTransportFailureType.transformTimeout,
      ];

      for (final type in timeouts) {
        final presentation = ApiFailurePresentation.of(
          ApiTransportFailure(type: type),
        );

        expect(presentation.kind, ApiFailureKind.timeout, reason: '$type');
        expect(presentation.isConnectivity, isTrue, reason: '$type');
        expect(presentation.canRetry, isTrue, reason: '$type');
      }
    });

    test('취소는 연결 문제가 아니며 재시도 버튼을 띄우지 않는다', () {
      final presentation = ApiFailurePresentation.of(
        const ApiTransportFailure(type: ApiTransportFailureType.cancelled),
      );

      expect(presentation.kind, ApiFailureKind.cancelled);
      expect(presentation.isConnectivity, isFalse);
      expect(presentation.canRetry, isFalse);
    });

    test('분류 불가 전송 실패는 unknown으로 두되 재시도는 허용한다', () {
      final presentation = ApiFailurePresentation.of(
        const ApiTransportFailure(type: ApiTransportFailureType.unknown),
      );

      expect(presentation.kind, ApiFailureKind.unknown);
      expect(presentation.canRetry, isTrue);
    });
  });

  group('ApiFailurePresentation.of — 응답 실패', () {
    ApiFailurePresentation presentationFor(int? statusCode) =>
        ApiFailurePresentation.of(
          ApiResponseFailure(statusCode: statusCode, error: null),
        );

    test('5xx는 서버 문제로 분류하고 재시도를 허용한다', () {
      for (final statusCode in [500, 502, 503]) {
        final presentation = presentationFor(statusCode);

        expect(presentation.kind, ApiFailureKind.server, reason: '$statusCode');
        expect(presentation.canRetry, isTrue, reason: '$statusCode');
        expect(presentation.isConnectivity, isFalse, reason: '$statusCode');
      }
    });

    test('401·403·404는 재시도해도 결과가 같으므로 재시도를 막는다', () {
      expect(presentationFor(401).kind, ApiFailureKind.unauthorized);
      expect(presentationFor(401).canRetry, isFalse);
      expect(presentationFor(401).message, contains('로그인'));

      expect(presentationFor(403).kind, ApiFailureKind.forbidden);
      expect(presentationFor(403).canRetry, isFalse);

      expect(presentationFor(404).kind, ApiFailureKind.notFound);
      expect(presentationFor(404).canRetry, isFalse);
    });

    test('그 밖의 4xx는 client로 모은다', () {
      expect(presentationFor(400).kind, ApiFailureKind.client);
      expect(presentationFor(422).kind, ApiFailureKind.client);
      expect(presentationFor(400).canRetry, isFalse);
    });

    test('상태 코드가 없으면 unknown으로 떨어뜨린다', () {
      expect(presentationFor(null).kind, ApiFailureKind.unknown);
    });

    test('3xx 이하 예상 밖 코드도 unknown으로 처리해 화면이 비지 않게 한다', () {
      expect(presentationFor(302).kind, ApiFailureKind.unknown);
    });
  });

  group('ApiFailurePresentation.of — 그 밖의 예외', () {
    test('ApiFailure가 아닌 객체도 unknown으로 안전하게 변환한다', () {
      expect(
        ApiFailurePresentation.of(FormatException('bad json')).kind,
        ApiFailureKind.unknown,
      );
      expect(ApiFailurePresentation.of(null).kind, ApiFailureKind.unknown);
    });
  });

  group('아동 모드 문구', () {
    test('연결 문제는 쉬운 말로 다시 해보자고 안내한다', () {
      final presentation = ApiFailurePresentation.of(
        const ApiTransportFailure(type: ApiTransportFailureType.connection),
        childFriendly: true,
      );

      expect(presentation.message, '연결이 잠깐 끊겼어요. 다시 해볼까요?');
    });

    test('원인이 무엇이든 아동에게 오류 상세를 노출하지 않는다', () {
      const causes = [401, 403, 500, 400];

      for (final statusCode in causes) {
        final presentation = ApiFailurePresentation.of(
          ApiResponseFailure(statusCode: statusCode, error: null),
          childFriendly: true,
        );

        expect(presentation.message, '지금은 잘 안 돼요. 조금 뒤에 다시 해볼까요?');
        expect(presentation.message, isNot(contains('로그인')));
        expect(presentation.message, isNot(contains('권한')));
        expect(presentation.message, isNot(contains('서버')));
      }
    });
  });
}
