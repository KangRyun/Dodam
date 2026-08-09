package com.ssafy.b209.drawing.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willThrow;
import static org.mockito.Mockito.verifyNoInteractions;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.domain.ChildFixture;
import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.child.repository.ChildRepository;
import com.ssafy.b209.drawing.domain.DrawingActivityCategory;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.domain.DrawingTypeFixture;
import com.ssafy.b209.drawing.domain.DrawingTypeSelectableBy;
import com.ssafy.b209.drawing.dto.response.DrawingTypePageResponse;
import com.ssafy.b209.drawing.repository.DrawingTypeRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class DrawingTypeQueryServiceTest {

  private static final Long GUARDIAN_USER_ID = 41L;
  private static final Long CHILD_ID = 7L;
  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;
  @Mock private GuardianResourceAccessValidator accessValidator;
  @Mock private ChildRepository childRepository;
  @Mock private DrawingTypeRepository drawingTypeRepository;

  private DrawingTypeQueryService service;

  @BeforeEach
  void setUp() {
    service =
        new DrawingTypeQueryService(
            currentUserResolver, accessValidator, childRepository, drawingTypeRepository);
  }

  @Test
  void rejectsChildWithoutGuardianAccessBeforeReadingProfileOrTypes() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    willThrow(new BusinessException(ChildErrorCode.CHILD_NOT_FOUND))
        .given(accessValidator)
        .requireChildAccess(GUARDIAN_USER_ID, CHILD_ID);

    assertThatThrownBy(
            () -> service.getDrawingTypes(CHILD_ID, DrawingActivityCategory.GENERAL, true))
        .isInstanceOf(BusinessException.class);

    verifyNoInteractions(childRepository, drawingTypeRepository);
  }

  @Test
  void returnsAllListedTypesRegardlessOfRecommendedAgeInDisplayOrder() {
    Child child =
        ChildFixture.create(
            CHILD_ID,
            LocalDate.of(2020, 7, 24),
            ChildTutorialStatus.COMPLETED,
            ChildProfileStatus.ACTIVE,
            null);
    DrawingType later = drawingType(12L, "ART_DIARY", 2, 3, 12);
    DrawingType first = drawingType(11L, "FREE_DRAWING", 1, null, null);
    DrawingType tooOld = drawingType(13L, "TODDLER_COLOR", 3, 1, 5);

    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_USER_ID);
    given(childRepository.findById(CHILD_ID)).willReturn(Optional.of(child));
    given(drawingTypeRepository.findForListing(DrawingActivityCategory.GENERAL, true))
        .willReturn(List.of(later, tooOld, first));

    DrawingTypePageResponse response =
        service.getDrawingTypes(CHILD_ID, DrawingActivityCategory.GENERAL, true);

    assertThat(response.content()).hasSize(3);
    assertThat(response.content())
        .extracting("code")
        .containsExactly("FREE_DRAWING", "ART_DIARY", "TODDLER_COLOR");
    assertThat(response.content().getFirst().guideText()).isEqualTo("자유롭게 그려 보세요.");
    assertThat(response.content().getFirst().displayOrder()).isEqualTo(1);
    assertThat(response.page()).isZero();
    assertThat(response.size()).isEqualTo(3);
    assertThat(response.totalElements()).isEqualTo(3);
    assertThat(response.totalPages()).isEqualTo(1);
    assertThat(response.hasNext()).isFalse();
  }

  private DrawingType drawingType(
      Long id,
      String code,
      int displayOrder,
      Integer recommendedAgeMin,
      Integer recommendedAgeMax) {
    DrawingType drawingType =
        DrawingTypeFixture.create(
            id,
            code,
            code,
            DrawingTypeSelectableBy.BOTH,
            recommendedAgeMin,
            recommendedAgeMax,
            true);
    ReflectionTestUtils.setField(drawingType, "guideText", "자유롭게 그려 보세요.");
    ReflectionTestUtils.setField(drawingType, "displayOrder", (short) displayOrder);
    return drawingType;
  }
}
