import 'package:flutter/foundation.dart';

import '../../../child/data/dto/child_consent_dtos.dart';
import '../../domain/repositories/consent_repository.dart';

enum ConsentSectionStatus { loading, ready, error }

/// 화면 표시용 동의 항목. 약관(제목·필수여부)과 현황(동의여부)을 조인한 결과.
class ConsentView {
  const ConsentView({
    required this.termId,
    required this.title,
    required this.required,
    required this.agreed,
    this.version = '',
    this.contentHtml,
    this.contentUrl,
  });

  final int termId;
  final String title;
  final bool required;
  final bool agreed;
  final String version;

  /// 약관 본문(HTML). 상세 보기에 사용한다.
  final String? contentHtml;
  final String? contentUrl;
}

/// 설정 > 동의 관리 상태. 보호자 본인 동의와 선택 아동 동의를 각각 조회하고,
/// 선택 약관의 철회/재동의를 처리한다.
final class ConsentManagementController extends ChangeNotifier {
  ConsentManagementController(this._repository);

  final ConsentRepository _repository;
  bool _disposed = false;

  ConsentSectionStatus guardianStatus = ConsentSectionStatus.loading;
  List<ConsentView> guardianConsents = const [];
  Object? guardianError;

  int? selectedChildId;
  ConsentSectionStatus childStatus = ConsentSectionStatus.ready;
  List<ConsentView> childConsents = const [];
  Object? childError;

  final Set<int> _pending = <int>{};

  /// 해당 약관이 변경 처리 중인지(토글 잠금·스피너용).
  bool isPending(int termId) => _pending.contains(termId);

  Future<void> loadGuardian() async {
    guardianStatus = ConsentSectionStatus.loading;
    guardianError = null;
    _safeNotify();
    try {
      guardianConsents = await _loadScope(ConsentTargetScope.user, null);
      guardianStatus = ConsentSectionStatus.ready;
    } on Object catch (error) {
      guardianError = error;
      guardianStatus = ConsentSectionStatus.error;
    }
    _safeNotify();
  }

  Future<void> selectChild(int? childId) async {
    selectedChildId = childId;
    childError = null;
    if (childId == null) {
      childConsents = const [];
      childStatus = ConsentSectionStatus.ready;
      _safeNotify();
      return;
    }
    childStatus = ConsentSectionStatus.loading;
    _safeNotify();
    try {
      childConsents = await _loadScope(ConsentTargetScope.child, childId);
      childStatus = ConsentSectionStatus.ready;
    } on Object catch (error) {
      childError = error;
      childStatus = ConsentSectionStatus.error;
    }
    _safeNotify();
  }

  /// 선택 약관을 켜기/끄기 한다. 성공하면 true(피드백 문구는 화면이 처리).
  ///
  /// 필수 약관은 화면에서 잠겨 있어 여기로 오지 않는다.
  Future<bool> setAgreed({
    required int termId,
    required bool agreed,
    int? childId,
  }) async {
    if (_pending.contains(termId)) return false;
    _pending.add(termId);
    _safeNotify();
    final agreement = agreed
        ? ConsentAgreementDto.agree(termId)
        : ConsentAgreementDto.withdraw(termId);
    try {
      await _repository.changeOptional(
        childId: childId,
        agreements: [agreement],
      );
      _pending.remove(termId);
      // 변경된 범위만 다시 조회해 최신 상태를 반영한다.
      if (childId == null) {
        await loadGuardian();
      } else {
        await selectChild(childId);
      }
      return true;
    } on Object {
      _pending.remove(termId);
      _safeNotify();
      return false;
    }
  }

  Future<List<ConsentView>> _loadScope(
    ConsentTargetScope scope,
    int? childId,
  ) async {
    final terms = await _repository.getTerms(scope);
    final status = await _repository.getStatus(childId: childId);
    final agreedByTerm = {
      for (final item in status.items) item.termId: item.agreed,
    };
    return terms
        .map(
          (term) => ConsentView(
            termId: term.termId,
            title: term.title,
            required: term.required,
            agreed: agreedByTerm[term.termId] ?? false,
            version: term.version,
            contentHtml: term.contentHtml,
            contentUrl: term.contentUrl,
          ),
        )
        .toList(growable: false);
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
