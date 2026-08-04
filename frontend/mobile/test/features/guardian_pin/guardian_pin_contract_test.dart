import 'package:dodam/features/guardian_pin/data/dto/guardian_pin_dtos.dart';
import 'package:dodam/features/guardian_pin/domain/failures/guardian_pin_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GuardianPinValidator', () {
    for (final pin in ['0123', '0000', '9999']) {
      test('$pin 숫자 4자리 문자열을 허용한다', () {
        expect(GuardianPinValidator.isValid(pin), isTrue);
      });
    }

    for (final pin in ['', '123', '12345', '12a4', '１２３４', ' 1234']) {
      test('${pin.isEmpty ? 'empty' : pin} 형식을 거부한다', () {
        expect(GuardianPinValidator.isValid(pin), isFalse);
      });
    }
  });

  group('GuardianPinStatusDto', () {
    test('성공·실패 공통 상태와 UTC 시간을 파싱한다', () {
      final status = GuardianPinStatusDto.fromJson({
        'pinConfigured': true,
        'locked': true,
        'remainingAttempts': 0,
        'retryAfterSeconds': 30.0,
        'lockedUntil': '2026-08-04T01:02:33Z',
        'serverTime': '2026-08-04T01:02:03Z',
      });

      expect(status.pinConfigured, isTrue);
      expect(status.locked, isTrue);
      expect(status.remainingAttempts, 0);
      expect(status.retryAfterSeconds, 30);
      expect(status.lockedUntil, DateTime.utc(2026, 8, 4, 1, 2, 33));
      expect(status.serverTime, DateTime.utc(2026, 8, 4, 1, 2, 3));
    });

    test('잠기지 않은 nullable 필드를 허용한다', () {
      final status = GuardianPinStatusDto.fromJson({
        'pinConfigured': false,
        'locked': false,
        'remainingAttempts': 5,
        'retryAfterSeconds': null,
        'lockedUntil': null,
        'serverTime': '2026-08-04T01:02:03Z',
      });

      expect(status.retryAfterSeconds, isNull);
      expect(status.lockedUntil, isNull);
    });

    test('분수 초와 timezone 없는 시각은 malformed 응답으로 거부한다', () {
      expect(
        () => GuardianPinStatusDto.fromJson({
          'pinConfigured': true,
          'locked': false,
          'remainingAttempts': 4,
          'retryAfterSeconds': 1.5,
          'lockedUntil': null,
          'serverTime': '2026-08-04T01:02:03Z',
        }),
        throwsFormatException,
      );
      expect(
        () => GuardianPinStatusDto.fromJson({
          'pinConfigured': true,
          'locked': false,
          'remainingAttempts': 4,
          'retryAfterSeconds': null,
          'lockedUntil': null,
          'serverTime': '2026-08-04T01:02:03',
        }),
        throwsFormatException,
      );
    });
  });

  test('PIN request와 failure 문자열은 원문을 노출하지 않는다', () {
    const request = GuardianPinRequestDto('0123');
    const change = GuardianPinChangeRequestDto(
      currentPin: '0123',
      newPin: '4567',
    );
    const failure = GuardianPinFailure(
      type: GuardianPinFailureType.mismatch,
      code: 'PIN_MISMATCH',
    );

    for (final value in [request.toString(), change.toString(), '$failure']) {
      expect(value, isNot(contains('0123')));
      expect(value, isNot(contains('4567')));
    }
  });
}
