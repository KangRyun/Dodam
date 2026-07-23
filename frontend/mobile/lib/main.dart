import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/router/app_routes.dart';
import 'features/auth/auth.dart';

void main() {
  runApp(
    DodamApp(
      authSessionStore: SecureAuthSessionStore(),
      initialRoute: AppRoutes.authBootstrap,
    ),
  );
}
