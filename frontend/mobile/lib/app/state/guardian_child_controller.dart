import 'package:flutter/foundation.dart';

import '../../features/child/data/dto/child_dtos.dart';
import '../../features/child/domain/repositories/child_repository.dart';

enum ChildListStatus { idle, loading, success, empty, error }

final class GuardianChildController extends ChangeNotifier {
  GuardianChildController(this._repository);

  final ChildRepository _repository;
  ChildListStatus _status = ChildListStatus.idle;
  List<ChildSummaryDto> _children = const [];
  ChildSummaryDto? _selectedChild;

  ChildListStatus get status => _status;
  List<ChildSummaryDto> get children => _children;
  ChildSummaryDto? get selectedChild => _selectedChild;
  int? get selectedChildId => _selectedChild?.childId;

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

  bool hasSelectedChild(int childId) => _selectedChild?.childId == childId;
}
