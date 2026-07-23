import 'package:dodam/core/config/api_environment.dart';
import 'package:dodam/app/app.dart';
import 'package:dodam/features/auth/auth.dart';
import 'package:dodam/features/drawing/data/repositories/mock_drawing_repository.dart';
import 'package:dodam/features/drawing/data/repositories/remote_drawing_repository.dart';
import 'package:dodam/main.dart' as app_main;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'normal app bootstrap uses RemoteDrawingRepository without a request',
    () {
      final app = app_main.createDefaultApp(
        environment: ApiEnvironment.fromBaseUrl('https://api.example.com'),
        authSessionStore: InMemoryAuthSessionStore(),
      );

      expect(app.drawingRepository, isA<RemoteDrawingRepository>());
      expect(app.authRepository, isA<AuthRepositoryImpl>());
    },
  );

  test('explicit DodamApp injection can keep MockDrawingRepository', () {
    const mock = MockDrawingRepository();
    const app = DodamApp(drawingRepository: mock);

    expect(app.drawingRepository, same(mock));
  });
}
