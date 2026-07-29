import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/app/app.dart';
import 'package:dodam/features/activity/data/repositories/remote_activity_repository.dart';
import 'package:dodam/features/auth/auth.dart';
import 'package:dodam/features/child/data/repositories/remote_child_repository.dart';
import 'package:dodam/features/conversation/data/repositories/remote_conversation_answer_repository.dart';
import 'package:dodam/features/conversation/data/repositories/remote_conversation_end_repository.dart';
import 'package:dodam/features/conversation/data/repositories/remote_conversation_repository.dart';
import 'package:dodam/features/conversation/data/repositories/remote_question_tts_repository.dart';
import 'package:dodam/features/drawing/data/repositories/mock_drawing_repository.dart';
import 'package:dodam/features/drawing/data/repositories/remote_drawing_repository.dart';
import 'package:dodam/features/report/data/repositories/remote_report_repository.dart';
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
    expect(app.questionTtsRepository, isA<RemoteQuestionTtsRepository>());
    expect(app.questionAudioPlayerFactory, isNotNull);
    expect(app.drawingRepository, isA<RemoteDrawingRepository>());
    expect(app.reportRepository, isA<RemoteReportRepository>());
    // Activity now uses the real backend API (S15P11B209 activity 연동).
    expect(app.activityRepository, isA<RemoteActivityRepository>());
    expect(app.authRepository, isA<RemoteAuthRepository>());
  });

  test('explicit DodamApp injection can keep MockDrawingRepository', () {
    const mock = MockDrawingRepository();
    const app = DodamApp(drawingRepository: mock);

    expect(app.drawingRepository, same(mock));
  });
}
