abstract final class AppRoutes {
  static const String authBootstrap = '/auth/bootstrap';
  static const String login = '/auth/login';
  static const String profileSelection = '/profiles/select';
  static const String expertProfile = '/expert/profile';
  static const String guardianHome = '/guardian/home';
  static const String childSelect = '/guardian/children/select';
  static const String childRegister = '/guardian/children/register';
  static String childEdit(String childId) =>
      '/guardian/children/${Uri.encodeComponent(childId)}/edit';
  static const String activityHistory = '/guardian/activities';
  static const String reportList = '/guardian/reports';

  // 아직 전용 화면이 없어 자리표시자로 매핑해 둔 보호자 영역 경로.
  // 담당 화면이 완성되면 app_router.dart의 해당 switch arm만 교체한다.
  static const String community =
      '/guardian/community'; // COMM-01 GET /posts (웹뷰 예정)
  static const String notifications =
      '/guardian/notifications'; // NOTI-03 GET /notifications (S15P11B209-499)
  static const String settings =
      '/guardian/settings'; // USER-01/04 /users/me (S15P11B209-454)

  static String childModeHome(String childId) =>
      '/child/${Uri.encodeComponent(childId)}/home';

  static String drawing(String childId) =>
      '/child/${Uri.encodeComponent(childId)}/activity/drawing';

  static String drawingActivitySelection(String childId) =>
      '/child/${Uri.encodeComponent(childId)}/activity/select';

  static String drawingInputMethod(String childId) =>
      '/child/${Uri.encodeComponent(childId)}/activity/input-method';

  static String emotionSelect(String childId) =>
      '/child/${Uri.encodeComponent(childId)}/activity/emotions';

  static String activityComplete(String childId) =>
      '/child/${Uri.encodeComponent(childId)}/activity/complete';

  static String guardianConfirm(String activityId) =>
      '/guardian/activities/${Uri.encodeComponent(activityId)}/confirm';

  static String activityDetail(String activityId) =>
      '/guardian/activities/${Uri.encodeComponent(activityId)}';

  static String report(String reportId) =>
      '/guardian/reports/${Uri.encodeComponent(reportId)}';
}
