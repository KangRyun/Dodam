import 'package:flutter/foundation.dart';

import '../../../child/data/dto/child_consent_dtos.dart';
import '../../domain/repositories/consent_repository.dart';

enum ConsentTermsStatus { loading, ready, error }

/// 적용 범위로 묶은 약관 한 덩어리.
///
/// [scope]가 `null`이면 서버가 범위를 주지 않았거나 앱이 모르는 범위다. 그런
/// 약관도 목록에서 빠지지 않게 마지막 덩어리로 모은다.
class ConsentTermGroup {
  const ConsentTermGroup({required this.scope, required this.terms});

  final ConsentTargetScope? scope;
  final List<ConsentTermDto> terms;
}

/// 설정 > 약관 및 정책 상태. 활성 약관 목록을 읽기 전용으로 조회한다.
///
/// 동의 현황(`GET /consents`)은 조회하지 않는다. 이 화면은 "무엇에 동의했는가"가
/// 아니라 "어떤 약관·정책이 있는가"를 보여주며, 동의 변경은 동의 관리 화면
/// (S15P11B209-706)의 몫이다.
final class ConsentTermsController extends ChangeNotifier {
  ConsentTermsController(this._repository);

  final ConsentRepository _repository;
  bool _disposed = false;

  /// 늦게 도착한 이전 조회 응답이 최신 상태를 덮지 않게 하는 카운터.
  int _generation = 0;

  ConsentTermsStatus status = ConsentTermsStatus.loading;
  List<ConsentTermDto> terms = const [];
  Object? error;

  /// 적용 범위별로 묶은 약관. 보호자 대상 → 아동 대상 → 범위 미상 순이며,
  /// 각 덩어리 안에서는 서버가 준 순서를 유지한다. 빈 덩어리는 제외한다.
  List<ConsentTermGroup> get groups {
    final groups = <ConsentTermGroup>[];
    for (final scope in [...ConsentTargetScope.values, null]) {
      final scoped = terms
          .where((term) => term.targetScope == scope)
          .toList(growable: false);
      if (scoped.isNotEmpty) {
        groups.add(ConsentTermGroup(scope: scope, terms: scoped));
      }
    }
    return groups;
  }

  /// 활성 약관 전 범위를 한 번의 요청으로 조회한다.
  ///
  /// `targetScope`를 붙이지 않는다. 서버가 그 Query를 생략하면 범위 필터를 걸지
  /// 않으므로 USER·CHILD를 나눠 두 번 부를 필요가 없고, 그만큼 "한쪽만 성공한"
  /// 부분 실패 상태도 생기지 않는다.
  Future<void> load() async {
    final generation = ++_generation;
    status = ConsentTermsStatus.loading;
    error = null;
    _safeNotify();
    try {
      final loaded = await _repository.getTerms();
      if (generation != _generation) return;
      terms = loaded;
      status = ConsentTermsStatus.ready;
    } on Object catch (failure) {
      if (generation != _generation) return;
      error = failure;
      status = ConsentTermsStatus.error;
    }
    _safeNotify();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
