import 'package:flutter/foundation.dart';

import '../../features/child/data/dto/child_dtos.dart';
import '../../features/child/domain/repositories/child_repository.dart';

enum ChildListStatus { idle, loading, success, empty, error }

enum ChildRegistrationStatus { idle, submitting, success, error }

final class GuardianChildController extends ChangeNotifier {
  GuardianChildController(this._repository);

  final ChildRepository _repository;
  ChildListStatus _status = ChildListStatus.idle;
  List<ChildSummaryDto> _children = const [];
  ChildSummaryDto? _selectedChild;
  ChildRegistrationStatus _registrationStatus = ChildRegistrationStatus.idle;
  Object? _registrationError;
  Object? _listError;

  ChildListStatus get status => _status;

  /// 목록 조회가 실패한 원인. 화면이 오프라인·서버 오류를 구분해 안내하는 데 쓴다.
  Object? get listError => _listError;
  List<ChildSummaryDto> get children => _children;
  ChildSummaryDto? get selectedChild => _selectedChild;
  int? get selectedChildId => _selectedChild?.childId;
  ChildRegistrationStatus get registrationStatus => _registrationStatus;
  Object? get registrationError => _registrationError;

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
    notifyListeners();
  }

  // 아동 등록 후 최신 목록을 다시 조회하고 등록한 아동을 선택
  Future<bool> registerChild(CreateChildRequestDto request) async {
    if (_registrationStatus == ChildRegistrationStatus.submitting) return false;
    _registrationStatus = ChildRegistrationStatus.submitting;
    _registrationError = null;
    notifyListeners();

    try {
      final created = await _repository.createChild(request);
      await loadChildren();
      if (_status == ChildListStatus.error) {
        throw StateError('아동 목록을 갱신하지 못했습니다.');
      }
      _selectedChild = _children.cast<ChildSummaryDto?>().firstWhere(
        (child) => child?.childId == created.childId,
        orElse: () => null,
      );
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
        _registrationError == null) {
      return;
    }
    _registrationStatus = ChildRegistrationStatus.idle;
    _registrationError = null;
    notifyListeners();
  }

  // 로그아웃 시 보호자 선택 상태 초기화
  void clearSelection() {
    if (_selectedChild == null) return;
    _selectedChild = null;
    notifyListeners();
  }

  /// 로그아웃한 계정의 아동 정보가 다음 인증 세션에 남지 않도록 전체 상태를 초기화한다.
  void clear() {
    _status = ChildListStatus.idle;
    _children = const [];
    _selectedChild = null;
    _listError = null;
    _registrationStatus = ChildRegistrationStatus.idle;
    _registrationError = null;
    notifyListeners();
  }

  bool hasSelectedChild(int childId) => _selectedChild?.childId == childId;
}
