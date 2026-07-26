import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/app/app.dart';
import 'package:dodam/features/activity/data/repositories/mock_activity_repository.dart';
import 'package:dodam/features/auth/auth.dart';
import 'package:dodam/features/child/data/repositories/remote_child_repository.dart';
import 'package:dodam/features/conversation/data/repositories/remote_conversation_answer_repository.dart';
import 'package:dodam/features/conversation/data/repositories/remote_conversation_end_repository.dart';
import 'package:dodam/features/conversation/data/repositories/remote_conversation_repository.dart';
import 'package:dodam/features/drawing/data/repositories/mock_drawing_repository.dart';
import 'package:dodam/features/drawing/data/repositories/remote_drawing_repository.dart';
import 'package:dodam/features/report/data/repositories/mock_report_repository.dart';
import 'package:dodam/main.dart' as app_main;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normal app bootstrap uses remote repositories without a request', () {
    final app = app_main.createDefaultApp(
      environment: ApiEnvironment.fromBaseUrl('https://api.example.com'),
      authSessionStore: InMemoryAuthSessionStore(),
    );

    expect(app.childRepository, isA<RemoteChildRepository>());
    expect(app.conversationRepository, isA<RemoteConversationRepository>());
    expect(
      app.conversationEndRepository,
      isA<RemoteConversationEndRepository>(),
    );
    expect(
      app.conversationAnswerRepository,
      isA<RemoteConversationAnswerRepository>(),
    );
    expect(app.drawingRepository, isA<RemoteDrawingRepository>());
    // Activity·report keep mock defaults until their backend APIs exist
    // (S15P11B209-384 contract check).
    expect(app.activityRepository, isA<MockActivityRepository>());
    expect(app.reportRepository, isA<MockReportRepository>());
    expect(app.authRepository, isA<RemoteAuthRepository>());
  });

  test('explicit DodamApp injection can keep MockDrawingRepository', () {
    const mock = MockDrawingRepository();
    const app = DodamApp(drawingRepository: mock);

    expect(app.drawingRepository, same(mock));
  });
}
