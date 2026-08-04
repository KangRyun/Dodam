import 'package:flutter/foundation.dart';

import '../../../core/network/api_failure_presentation.dart';
import '../data/dto/notification_settings_dtos.dart';
import '../domain/repositories/notification_settings_repository.dart';

/// 알림 수신 설정 조회의 진행 상태.
enum NotificationSettingsStatus { loading, ready, error }

/// 알림 수신 설정 조회·편집·저장 상태를 관리한다(S15P11B209-455).
///
/// 저장은 계약대로 **네 필드 전체 교체**다(`PATCH` 이지만 부분 수정이 아니다 —
/// `notification-settings-update-contract.md` §0-1). 그래서 화면이 토글마다 서버로
/// 보내지 않고, 편집값을 여기 모아 두었다가 [save] 에서 네 값을 한 번에 보낸다.
/// 토글마다 보내면 요청이 네 배로 늘고, 중간 요청이 실패했을 때 화면과 서버가
/// 어긋난 상태로 남는다.
///
/// 계약: `docs/api/notification-settings-read-contract.md`,
/// `docs/api/notification-settings-update-contract.md`
final class NotificationSettingsController extends ChangeNotifier {
  NotificationSettingsController(this._repository);

  final NotificationSettingsRepository _repository;

  NotificationSettingsStatus _status = NotificationSettingsStatus.loading;
  Object? _error;

  /// 편집 중인 값. 조회 전에는 없다.
  NotificationSettingsDto? _settings;

  /// 마지막으로 저장된(= 서버와 일치하는) 값. 편집값과 비교해 dirty 를 판단한다.
  NotificationSettingsDto? _savedSettings;

  bool _isSaving = false;
  Object? _saveError;
  bool _disposed = false;
  int _generation = 0;

  NotificationSettingsStatus get status => _status;
  Object? get error => _error;
  NotificationSettingsDto? get settings => _settings;
  bool get isSaving => _isSaving;

  /// 저장 이후 편집으로 값이 바뀌었는지.
  bool get isDirty {
    final settings = _settings;
    final saved = _savedSettings;
    if (settings == null || saved == null) return false;
    return settings.analysisCompleted != saved.analysisCompleted ||
        settings.community != saved.community ||
        settings.serviceNotice != saved.serviceNotice ||
        settings.marketing != saved.marketing;
  }

  /// 저장 버튼을 열 수 있는지. 준비 완료 + 바뀐 값 + 저장 중 아님.
  bool get canSave =>
      _status == NotificationSettingsStatus.ready && isDirty && !_isSaving;

  /// 저장 실패 시 화면에 띄울 문구. 실패가 없으면 `null`.
  String? get saveFailureMessage {
    final error = _saveError;
    if (error == null) return null;
    return ApiFailurePresentation.of(error).message;
  }

  Future<void> load() async {
    final generation = ++_generation;
    _status = NotificationSettingsStatus.loading;
    _error = null;
    _notify();

    try {
      final settings = await _repository.getNotificationSettings();
      if (_disposed || generation != _generation) return;
      _applyLoaded(settings);
      _status = NotificationSettingsStatus.ready;
      _notify();
    } on Object catch (error) {
      if (_disposed || generation != _generation) return;
      _status = NotificationSettingsStatus.error;
      _error = error;
      _notify();
    }
  }

  void setAnalysisCompleted(bool value) =>
      _edit((settings) => settings.copyWith(analysisCompleted: value));

  void setCommunity(bool value) =>
      _edit((settings) => settings.copyWith(community: value));

  void setServiceNotice(bool value) =>
      _edit((settings) => settings.copyWith(serviceNotice: value));

  void setMarketing(bool value) =>
      _edit((settings) => settings.copyWith(marketing: value));

  /// 네 값을 한 번에 저장하고 성공 여부를 반환한다. [canSave] 가 거짓이면 보내지 않는다.
  Future<bool> save() async {
    if (!canSave) return false;
    final settings = _settings;
    if (settings == null) return false;

    final generation = ++_generation;
    _isSaving = true;
    _saveError = null;
    _notify();

    try {
      final saved = await _repository.updateNotificationSettings(settings);
      if (_disposed || generation != _generation) return false;
      // 응답이 저장 후 최신 값이므로(계약 §0-3) 그것으로 편집값까지 맞춘다.
      _applyLoaded(saved);
      _isSaving = false;
      _notify();
      return true;
    } on Object catch (error) {
      if (_disposed || generation != _generation) return false;
      _isSaving = false;
      _saveError = error;
      _notify();
      return false;
    }
  }

  void _edit(
    NotificationSettingsDto Function(NotificationSettingsDto settings) change,
  ) {
    final settings = _settings;
    if (settings == null || _isSaving) return;
    _settings = change(settings);
    _saveError = null;
    _notify();
  }

  void _applyLoaded(NotificationSettingsDto settings) {
    _settings = settings;
    _savedSettings = settings;
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
