import 'package:flutter/foundation.dart';

import '../../features/child/data/dto/child_consent_dtos.dart';
import '../../features/child/data/dto/child_dtos.dart';
import '../../features/child/data/repositories/mock_child_consent_repository.dart';
import '../../features/child/domain/repositories/child_consent_repository.dart';
import '../../features/child/domain/repositories/child_repository.dart';

enum ChildListStatus { idle, loading, success, empty, error }

enum ChildRegistrationStatus { idle, submitting, success, error }

final class GuardianChildController extends ChangeNotifier {
  GuardianChildController(
    this._repository, [
    this._consentRepository = const MockChildConsentRepository(),
  ]);

  final ChildRepository _repository;
  final ChildConsentRepository _consentRepository;
  ChildListStatus _status = ChildListStatus.idle;
  List<ChildSummaryDto> _children = const [];
  ChildSummaryDto? _selectedChild;
  bool _hasExplicitChildSelection = false;
  ChildRegistrationStatus _registrationStatus = ChildRegistrationStatus.idle;
  Object? _registrationError;
  Object? _listError;
  List<ConsentTermDto> _childConsentTerms = const [];
  Object? _consentRecordError;

  ChildListStatus get status => _status;

  /// 목록 조회가 실패한 원인. 화면이 오프라인·서버 오류를 구분해 안내하는 데 쓴다.
  Object? get listError => _listError;
  List<ChildSummaryDto> get children => _children;

  /// 목록 조회로 **확정된** 아동 수. 아직 확인하지 못했으면 `null`.
  ///
  /// 조회 실패([ChildListStatus.error])나 조회 전([ChildListStatus.idle],
  /// [ChildListStatus.loading])에도 [children]은 빈 목록이라, 길이만 보면
  /// "아이가 없는 계정"과 구분되지 않는다. 없다고 단정하면 위험한 화면
  /// (회원 탈퇴 안내 등)은 이 값을 써야 한다.
  int? get confirmedChildCount => switch (_status) {
    ChildListStatus.success || ChildListStatus.empty => _children.length,
    ChildListStatus.idle ||
    ChildListStatus.loading ||
    ChildListStatus.error => null,
  };
  ChildSummaryDto? get selectedChild => _selectedChild;
  int? get selectedChildId => _selectedChild?.childId;
  bool get hasExplicitChildSelection => _hasExplicitChildSelection;
  ChildRegistrationStatus get registrationStatus => _registrationStatus;
  Object? get registrationError => _registrationError;

  /// 아동 등록 화면이 보여줄 아동 대상 약관. 조회 실패나 미지원 환경에서는 빈 목록이다.
  List<ConsentTermDto> get childConsentTerms => _childConsentTerms;

  /// 아동은 등록됐지만 동의 이력 기록이 실패한 경우의 원인.
  ///
  /// 이 값이 있으면 아동 데이터 동의가 비어 있어 음성 답변이 거절된다. 화면은 재동의를
  /// 안내해야 한다.
  Object? get consentRecordError => _consentRecordError;

  /// 아동 대상 약관을 조회한다. 실패하면 빈 목록으로 두어 등록 자체를 막지 않는다.
  Future<void> loadChildConsentTerms() async {
    try {
      _childConsentTerms = await _consentRepository.getChildTerms();
    } on Object catch (_) {
      _childConsentTerms = const [];
    }
    notifyListeners();
  }

  Future<void> loadChildren() async {
    _status = ChildListStatus.loading;
    _listError = null;
    notifyListeners();
    try {
      final children = await _repository.getChildren();
      _children = children;
      if (_selectedChild case final selected?) {
        _selectedChild = children.cast<ChildSummaryDto?>().firstWhere(
          (child) => child?.childId == selected.childId,
          orElse: () => null,
        );
        if (_selectedChild == null) _hasExplicitChildSelection = false;
      }
      // 첫 진입 시 첫 아이를 자동 선택해 보호자 홈 대시보드가 바로 데이터를
      // 보여준다(마음 카드·최근 활동·마음 달력). 선택 이력이 있으면 유지한다.
      _selectedChild ??= children.isEmpty ? null : children.first;
      _status = children.isEmpty
          ? ChildListStatus.empty
          : ChildListStatus.success;
    } on Object catch (error) {
      _listError = error;
      _status = ChildListStatus.error;
    }
    notifyListeners();
  }

  void selectChild(ChildSummaryDto child) {
    if (!_children.any((item) => item.childId == child.childId)) return;
    _selectedChild = child;
    _hasExplicitChildSelection = true;
    notifyListeners();
  }

  // 아동 등록 후 아동 대상 동의를 기록하고 최신 목록을 다시 조회해 등록한 아동을 선택
  Future<bool> registerChild(
    CreateChildRequestDto request, {
    List<ConsentAgreementDto> consentAgreements = const [],
  }) async {
    if (_registrationStatus == ChildRegistrationStatus.submitting) return false;
    _registrationStatus = ChildRegistrationStatus.submitting;
    _registrationError = null;
    _consentRecordError = null;
    notifyListeners();

    try {
      final created = await _repository.createChild(request);
      // 동의 기록 실패로 등록을 되돌리지 않는다. 아동 데이터를 지우는 편이 더 위험하고,
      // 동의는 설정에서 다시 기록할 수 있다. 대신 원인을 남겨 화면이 안내하게 한다.
      if (consentAgreements.isNotEmpty) {
        try {
          await _consentRepository.submitChildConsents(
            childId: created.childId,
            agreements: consentAgreements,
          );
        } on Object catch (error) {
          _consentRecordError = error;
        }
      }
      await loadChildren();
      if (_status == ChildListStatus.error) {
        throw StateError('아동 목록을 갱신하지 못했습니다.');
      }
      _selectedChild = _children.cast<ChildSummaryDto?>().firstWhere(
        (child) => child?.childId == created.childId,
        orElse: () => null,
      );
      _hasExplicitChildSelection = _selectedChild != null;
      _registrationStatus = ChildRegistrationStatus.success;
      notifyListeners();
      return true;
    } on Object catch (error) {
      _registrationError = error;
      _registrationStatus = ChildRegistrationStatus.error;
      notifyListeners();
      return false;
    }
  }

  // 아동 정보 수정 후 목록과 현재 선택 상태를 서버 응답 기준으로 갱신
  Future<bool> updateChild(int childId, UpdateChildRequestDto request) async {
    if (_registrationStatus == ChildRegistrationStatus.submitting) return false;
    _registrationStatus = ChildRegistrationStatus.submitting;
    _registrationError = null;
    notifyListeners();
    try {
      await _repository.updateChild(childId, request);
      await loadChildren();
      if (_status == ChildListStatus.error) {
        throw StateError('아동 목록을 갱신하지 못했습니다.');
      }
      _registrationStatus = ChildRegistrationStatus.success;
      notifyListeners();
      return true;
    } on Object catch (error) {
      _registrationError = error;
      _registrationStatus = ChildRegistrationStatus.error;
      notifyListeners();
      return false;
    }
  }

  /// 아동이 홈에서 고른 캐릭터를 그 아이의 `preferredCharacter`로 저장한다
  /// (S15P11B209-505). 프로필 이미지가 곧바로 바뀌도록 메모리 목록을 먼저
  /// 낙관적으로 갱신한 뒤, 백엔드 저장은 best-effort로 뒤따른다(전체 재조회 없이).
  ///
  /// 등록 수정(`updateChild`)과 달리 목록 전체를 다시 불러오지 않고, 등록 UI
  /// 상태(`_registrationStatus`)도 건드리지 않는다 — 아동 홈의 가벼운 배경 저장이다.
  Future<void> updateChildCharacter(int childId, String characterCode) async {
    final updated = <ChildSummaryDto>[];
    var changed = false;
    for (final child in _children) {
      if (child.childId == childId &&
          child.preferredCharacter != characterCode) {
        updated.add(child.copyWith(preferredCharacter: characterCode));
        changed = true;
      } else {
        updated.add(child);
      }
    }
    if (changed) {
      _children = updated;
      if (_selectedChild?.childId == childId) {
        _selectedChild = _selectedChild!.copyWith(
          preferredCharacter: characterCode,
        );
      }
      notifyListeners();
    }
    try {
      await _repository.updateChild(
        childId,
        UpdateChildRequestDto(preferredCharacter: characterCode),
      );
    } on Object {
      // 백엔드 저장 실패는 홈 사용을 막지 않는다. 화면 표시와 로컬 코스튬은
      // 유지되고, 다음 목록 조회 때 서버 값으로 다시 맞춰진다.
    }
  }

  // 삭제 완료 후 제거된 아동의 선택 상태를 비우고 최신 목록을 조회
  Future<bool> deleteChild(int childId) async {
    if (_registrationStatus == ChildRegistrationStatus.submitting) return false;
    _registrationStatus = ChildRegistrationStatus.submitting;
    _registrationError = null;
    notifyListeners();
    try {
      await _repository.deleteChild(childId);
      if (_selectedChild?.childId == childId) {
        _selectedChild = null;
        _hasExplicitChildSelection = false;
      }
      await loadChildren();
      if (_status == ChildListStatus.error) {
        throw StateError('아동 목록을 갱신하지 못했습니다.');
      }
      _registrationStatus = ChildRegistrationStatus.success;
      notifyListeners();
      return true;
    } on Object catch (error) {
      _registrationError = error;
      _registrationStatus = ChildRegistrationStatus.error;
      notifyListeners();
      return false;
    }
  }

  void resetRegistration() {
    if (_registrationStatus == ChildRegistrationStatus.idle &&
        _registrationError == null &&
        _consentRecordError == null) {
      return;
    }
    _registrationStatus = ChildRegistrationStatus.idle;
    _registrationError = null;
    _consentRecordError = null;
    notifyListeners();
  }

  // 로그아웃 시 보호자 선택 상태 초기화
  void clearSelection() {
    if (_selectedChild == null && !_hasExplicitChildSelection) return;
    _selectedChild = null;
    _hasExplicitChildSelection = false;
    notifyListeners();
  }

  /// 로그아웃한 계정의 아동 정보가 다음 인증 세션에 남지 않도록 전체 상태를 초기화한다.
  void clear() {
    _status = ChildListStatus.idle;
    _children = const [];
    _selectedChild = null;
    _hasExplicitChildSelection = false;
    _listError = null;
    _registrationStatus = ChildRegistrationStatus.idle;
    _registrationError = null;
    _consentRecordError = null;
    _childConsentTerms = const [];
    notifyListeners();
  }

  bool hasSelectedChild(int childId) => _selectedChild?.childId == childId;
}
