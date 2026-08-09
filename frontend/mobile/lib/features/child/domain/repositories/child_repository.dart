import '../../data/dto/child_dtos.dart';

abstract interface class ChildRepository {
  Future<List<ChildSummaryDto>> getChildren();
  Future<ChildDetailDto> createChild(CreateChildRequestDto request);
  Future<ChildDetailDto> getChild(int childId);
  Future<ChildDetailDto> updateChild(
    int childId,
    UpdateChildRequestDto request,
  );
  Future<void> deleteChild(int childId);
  Future<TutorialProgressDto> getTutorialProgress(int childId);
  Future<TutorialProgressDto> updateTutorialProgress(
    int childId,
    UpdateTutorialRequestDto request,
  );
}
