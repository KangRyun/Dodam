import 'package:flutter/material.dart';

import '../design_system/design_system.dart';
import 'router/app_router.dart';
import 'router/app_routes.dart';

class DodamApp extends StatelessWidget {
  const DodamApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '도담',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.leaf,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.canvas,
    ),
    initialRoute: AppRoutes.guardianHome,
    onGenerateRoute: AppRouter.onGenerateRoute,
  );
}
