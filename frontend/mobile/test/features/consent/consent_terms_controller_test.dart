import 'dart:async';

import 'package:dodam/features/child/data/dto/child_consent_dtos.dart';
import 'package:dodam/features/consent/data/dto/consent_status_dtos.dart';
import 'package:dodam/features/consent/domain/repositories/consent_repository.dart';
import 'package:dodam/features/consent/presentation/controllers/consent_terms_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const _serviceTos = ConsentTermDto(
  termId: 1,
  termCode: 'SERVICE_TOS',
  title: '서비스 이용약관',
  required: true,
  version: 'v1',
  targetScope: ConsentTargetScope.user,
);

const _marketing = ConsentTermDto(
  termId: 7,
  termCode: 'MARKETING',
  title: '마케팅 및 알림 수신',
  required: false,
  version: 'v1',
  targetScope: ConsentTargetScope.user,
);

const _voice = ConsentTermDto(
  termId: 4,
  termCode: 'VOICE_PROCESSING',
  title: '음성 데이터 처리',
  required: false,
  version: 'v1',
  targetScope: ConsentTargetScope.child,
);

void main() {
  group('ConsentTermsController', () {
    test('targetScope 없이 한 번만 조회해 전 범위 약관을 받는다', () async {
      final repository = _FakeConsentRepository(
        terms: const [_serviceTos, _voice, _marketing],
      );
      final controller = ConsentTermsController(repository);

      await controller.load();

      // 범위별로 나눠 두 번 부르면 한쪽만 성공하는 부분 실패가 생긴다.
      // 서버가 targetScope 생략을 전 범위로 처리하므로 호출은 한 번이어야 한다.
      expect(repository.scopeArguments, [null]);
      expect(controller.status, ConsentTermsStatus.ready);
      expect(controller.terms.map((term) => term.title), [
        '서비스 이용약관',
        '음성 데이터 처리',
        '마케팅 및 알림 수신',
      ]);
    });

    test('적용 범위별로 묶고 각 묶음 안에서는 서버 순서를 유지한다', () async {
      final repository = _FakeConsentRepository(
        terms: const [_serviceTos, _voice, _marketing],
      );
      final controller = ConsentTermsController(repository);

      await controller.load();

      final groups = controller.groups;
      expect(groups.map((group) => group.scope), [
        ConsentTargetScope.user,
        ConsentTargetScope.child,
      ]);
      expect(groups.first.terms.map((term) => term.title), [
        '서비스 이용약관',
        '마케팅 및 알림 수신',
      ]);
      expect(groups.last.terms.single.title, '음성 데이터 처리');
    });

    test('범위를 모르는 약관도 빠뜨리지 않고 마지막 묶음에 남긴다', () async {
      const unknownScope = ConsentTermDto(
        termId: 99,
        termCode: 'FUTURE_SCOPE',
        title: '새로 생긴 약관',
        required: false,
        version: 'v1',
      );
      final repository = _FakeConsentRepository(
        terms: const [unknownScope, _serviceTos],
      );
      final controller = ConsentTermsController(repository);

      await controller.load();

      expect(controller.groups.map((group) => group.scope), [
        ConsentTargetScope.user,
        null,
      ]);
      expect(controller.groups.last.terms.single.title, '새로 생긴 약관');
    });

    test('조회가 끝나기 전에는 loading을 유지한다', () async {
      final gate = Completer<List<ConsentTermDto>>();
      final repository = _FakeConsentRepository(gate: gate);
      final controller = ConsentTermsController(repository);

      final pending = controller.load();
      await Future<void>.delayed(Duration.zero);

      expect(controller.status, ConsentTermsStatus.loading);
      expect(controller.terms, isEmpty);

      gate.complete(const [_serviceTos]);
      await pending;

      expect(controller.status, ConsentTermsStatus.ready);
      expect(controller.terms.single.title, '서비스 이용약관');
    });

    test('조회에 실패하면 error 상태로 원인을 남기고, 재시도에 성공하면 목록을 채운다', () async {
      final failure = Exception('boom');
      final repository = _FakeConsentRepository(
        terms: const [_serviceTos],
        failure: failure,
      );
      final controller = ConsentTermsController(repository);

      await controller.load();

      expect(controller.status, ConsentTermsStatus.error);
      expect(controller.error, same(failure));
      expect(controller.terms, isEmpty);

      repository.failure = null;
      await controller.load();

      expect(controller.status, ConsentTermsStatus.ready);
      expect(controller.error, isNull);
      expect(controller.terms.single.title, '서비스 이용약관');
    });

    test('늦게 도착한 이전 조회 결과가 최신 결과를 덮지 않는다', () async {
      final first = Completer<List<ConsentTermDto>>();
      final second = Completer<List<ConsentTermDto>>();
      final repository = _FakeConsentRepository(gates: [first, second]);
      final controller = ConsentTermsController(repository);

      final firstLoad = controller.load();
      final secondLoad = controller.load();

      second.complete(const [_marketing]);
      await secondLoad;
      first.complete(const [_serviceTos]);
      await firstLoad;

      expect(controller.terms.single.title, '마케팅 및 알림 수신');
      expect(controller.status, ConsentTermsStatus.ready);
    });

    test('dispose 뒤에 조회가 끝나도 listener 통지로 터지지 않는다', () async {
      final gate = Completer<List<ConsentTermDto>>();
      final repository = _FakeConsentRepository(gate: gate);
      final controller = ConsentTermsController(repository);

      final pending = controller.load();
      controller.dispose();
      gate.complete(const [_serviceTos]);

      await expectLater(pending, completes);
    });
  });
}

final class _FakeConsentRepository implements ConsentRepository {
  _FakeConsentRepository({
    this.terms = const [],
    this.failure,
    Completer<List<ConsentTermDto>>? gate,
    List<Completer<List<ConsentTermDto>>>? gates,
  }) : _gates = [...?gates, ?gate];

  final List<ConsentTermDto> terms;
  Object? failure;
  final List<Completer<List<ConsentTermDto>>> _gates;

  final List<ConsentTargetScope?> scopeArguments = [];

  @override
  Future<List<ConsentTermDto>> getTerms([ConsentTargetScope? scope]) {
    scopeArguments.add(scope);
    if (_gates.isNotEmpty) return _gates.removeAt(0).future;
    final pendingFailure = failure;
    if (pendingFailure != null) return Future.error(pendingFailure);
    return Future.value(terms);
  }

  @override
  Future<ConsentStatusDto> getStatus({int? childId}) async =>
      throw StateError('약관 열람 화면은 동의 현황을 조회하지 않는다.');

  @override
  Future<void> changeOptional({
    int? childId,
    required List<ConsentAgreementDto> agreements,
  }) async => throw StateError('약관 열람 화면은 동의를 변경하지 않는다.');
}
