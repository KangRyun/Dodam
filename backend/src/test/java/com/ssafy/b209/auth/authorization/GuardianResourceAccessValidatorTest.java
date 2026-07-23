package com.ssafy.b209.auth.authorization;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;

import com.ssafy.b209.child.exception.ChildErrorCode;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class GuardianResourceAccessValidatorTest {

  private static final Long GUARDIAN_USER_ID = 41L;
  private static final Long CHILD_ID = 7L;
  private static final Long DRAWING_SESSION_ID = 9L;

  @Mock private GuardianResourceAccessRepository repository;

  @InjectMocks private GuardianResourceAccessValidator validator;

  @Test
  void allowsGuardianConnectedToChild() {
    given(repository.hasChildAccess(GUARDIAN_USER_ID, CHILD_ID)).willReturn(true);

    assertThatCode(() -> validator.requireChildAccess(GUARDIAN_USER_ID, CHILD_ID))
        .doesNotThrowAnyException();
  }

  @Test
  void hidesChildWhenGuardianIsNotConnected() {
    given(repository.hasChildAccess(GUARDIAN_USER_ID, CHILD_ID)).willReturn(false);

    assertThatThrownBy(() -> validator.requireChildAccess(GUARDIAN_USER_ID, CHILD_ID))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode()).isEqualTo(ChildErrorCode.CHILD_NOT_FOUND));
  }

  @Test
  void allowsGuardianConnectedToDrawingSessionChild() {
    given(repository.hasDrawingSessionAccess(GUARDIAN_USER_ID, DRAWING_SESSION_ID))
        .willReturn(true);

    assertThatCode(
            () -> validator.requireDrawingSessionAccess(GUARDIAN_USER_ID, DRAWING_SESSION_ID))
        .doesNotThrowAnyException();
  }

  @Test
  void hidesDrawingSessionWhenGuardianIsNotConnected() {
    given(repository.hasDrawingSessionAccess(GUARDIAN_USER_ID, DRAWING_SESSION_ID))
        .willReturn(false);

    assertThatThrownBy(
            () -> validator.requireDrawingSessionAccess(GUARDIAN_USER_ID, DRAWING_SESSION_ID))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(DrawingErrorCode.DRAWING_SESSION_NOT_FOUND));
  }
}
