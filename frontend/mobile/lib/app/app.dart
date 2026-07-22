import 'package:flutter/material.dart';

import '../design_system/design_system.dart';
import '../features/child/data/repositories/mock_child_repository.dart';
import '../features/child/domain/repositories/child_repository.dart';
import '../features/drawing/data/dto/drawing_dtos.dart';
import '../features/drawing/data/repositories/mock_drawing_repository.dart';
import '../features/drawing/domain/repositories/drawing_repository.dart';
import 'router/app_router.dart';
import 'router/app_routes.dart';
import 'state/guardian_child_controller.dart';

class DodamApp extends StatefulWidget {
  const DodamApp({
    this.childRepository = const MockChildRepository(),
    this.drawingRepository = const MockDrawingRepository(),
    this.drawingCompletionSnapshotProvider,
    this.initialRoute = AppRoutes.guardianHome,
    super.key,
  });

  final ChildRepository childRepository;
  final DrawingRepository drawingRepository;
  final Future<BinaryUploadDto?> Function()? drawingCompletionSnapshotProvider;
  final String initialRoute;

  @override
  State<DodamApp> createState() => _DodamAppState();
}

class _DodamAppState extends State<DodamApp> {
  late final GuardianChildController _childController;

  @override
  void initState() {
    super.initState();
    _childController = GuardianChildController(widget.childRepository);
    _childController.loadChildren();
  }

  @override
  void dispose() {
    _childController.dispose();
    super.dispose();
  }

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
    initialRoute: widget.initialRoute,
    onGenerateRoute: (settings) => AppRouter.onGenerateRoute(
      settings,
      childController: _childController,
      drawingRepository: widget.drawingRepository,
      drawingCompletionSnapshotProvider:
          widget.drawingCompletionSnapshotProvider,
    ),
  );
}
