abstract final class AppRoutes {
  static const String login = '/auth/login';
  static const String guardianHome = '/guardian/home';
  static const String childSelect = '/guardian/children/select';
  static const String activityHistory = '/guardian/activities';

  static String childModeHome(String childId) =>
      '/child/${Uri.encodeComponent(childId)}/home';

  static String drawing(String childId) =>
      '/child/${Uri.encodeComponent(childId)}/activity/drawing';

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
