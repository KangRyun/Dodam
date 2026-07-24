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

  ChildListStatus get status => _status;
  List<ChildSummaryDto> get children => _children;
  ChildSummaryDto? get selectedChild => _selectedChild;
  int? get selectedChildId => _selectedChild?.childId;
  ChildRegistrationStatus get registrationStatus => _registrationStatus;
  Object? get registrationError => _registrationError;

  Future<void> loadChildren() async {
    _status = ChildListStatus.loading;
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
      _status = children.isEmpty
          ? ChildListStatus.empty
          : ChildListStatus.success;
    } on Object {
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

  bool hasSelectedChild(int childId) => _selectedChild?.childId == childId;
}
