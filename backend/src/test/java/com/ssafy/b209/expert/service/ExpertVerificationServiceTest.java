package com.ssafy.b209.expert.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;

import com.ssafy.b209.auth.domain.User;
import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.repository.UserRepository;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.expert.domain.ExpertCredential;
import com.ssafy.b209.expert.domain.ExpertProfile;
import com.ssafy.b209.expert.domain.ExpertVerificationStatus;
import com.ssafy.b209.expert.dto.request.CreateExpertProfileRequest;
import com.ssafy.b209.expert.dto.request.ReviewExpertVerificationRequest;
import com.ssafy.b209.expert.dto.request.UploadExpertCredentialRequest;
import com.ssafy.b209.expert.exception.ExpertErrorCode;
import com.ssafy.b209.expert.repository.ExpertCredentialRepository;
import com.ssafy.b209.expert.repository.ExpertProfileRepository;
import com.ssafy.b209.expert.repository.ExpertVerificationAuditRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.notification.repository.NotificationRepository;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

class ExpertVerificationServiceTest {

  private static final Instant REVIEWED_AT = Instant.parse("2026-08-03T02:00:00Z");

  @Test
  void verifiesOnlySelectedCredentialsAndApprovesProfile() {
    Fixture fixture = new Fixture(UserRole.ADMIN);
    ExpertProfile profile = fixture.profile();
    ExpertCredential selected = fixture.credential(profile, 31L);
    ExpertCredential unselected = fixture.credential(profile, 32L);
    given(fixture.profileRepository.findById(9L)).willReturn(Optional.of(profile));
    given(fixture.credentialRepository.findAllForReview(9L))
        .willReturn(List.of(selected, unselected));

    var result =
        fixture.service.review(
            9L,
            new ReviewExpertVerificationRequest(
                ExpertVerificationStatus.VERIFIED, List.of(31L), null, "증빙 확인 완료"));

    assertThat(profile.getVerificationStatus()).isEqualTo(ExpertVerificationStatus.VERIFIED);
    assertThat(selected.getVerificationStatus()).isEqualTo(ExpertVerificationStatus.VERIFIED);
    assertThat(unselected.getVerificationStatus()).isEqualTo(ExpertVerificationStatus.PENDING);
    assertThat(result.reviewedAt()).isEqualTo(REVIEWED_AT);
    assertThat(result.credentials())
        .extracting(item -> item.credentialId() + ":" + item.verificationStatus())
        .containsExactly("31:VERIFIED", "32:PENDING");
    assertThat(fixture.savedNotification().getRecipientUserId()).isEqualTo(70L);
    assertThat(fixture.savedNotification().getNotificationType())
        .isEqualTo("EXPERT_VERIFICATION_RESULT");
  }

  @Test
  void rejectsProfileAndPendingCredentialsWhenReasonIsProvided() {
    Fixture fixture = new Fixture(UserRole.ADMIN);
    ExpertProfile profile = fixture.profile();
    ExpertCredential credential = fixture.credential(profile, 31L);
    given(fixture.profileRepository.findById(9L)).willReturn(Optional.of(profile));
    given(fixture.credentialRepository.findAllForReview(9L)).willReturn(List.of(credential));

    fixture.service.review(
        9L,
        new ReviewExpertVerificationRequest(
            ExpertVerificationStatus.REJECTED, List.of(), "증빙 식별 불가", null));

    assertThat(profile.getVerificationStatus()).isEqualTo(ExpertVerificationStatus.REJECTED);
    assertThat(credential.getVerificationStatus()).isEqualTo(ExpertVerificationStatus.REJECTED);
  }

  @Test
  void deniesVerificationToNonAdmin() {
    Fixture fixture = new Fixture(UserRole.EXPERT);

    assertThatThrownBy(
            () ->
                fixture.service.review(
                    9L,
                    new ReviewExpertVerificationRequest(
                        ExpertVerificationStatus.REJECTED, List.of(), "증빙 식별 불가", null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode()).isEqualTo(AuthErrorCode.ACCESS_DENIED));
  }

  @Test
  void requiresRejectionReasonForRejectedStatus() {
    Fixture fixture = new Fixture(UserRole.ADMIN);

    assertThatThrownBy(
            () ->
                fixture.service.review(
                    9L,
                    new ReviewExpertVerificationRequest(
                        ExpertVerificationStatus.REJECTED, List.of(), " ", null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ExpertErrorCode.EXPERT_VERIFICATION_REQUEST_INVALID));
  }

  @Test
  void rejectsCredentialIdThatDoesNotBelongToExpert() {
    Fixture fixture = new Fixture(UserRole.ADMIN);
    ExpertProfile profile = fixture.profile();
    given(fixture.profileRepository.findById(9L)).willReturn(Optional.of(profile));
    given(fixture.credentialRepository.findAllForReview(9L)).willReturn(List.of());

    assertThatThrownBy(
            () ->
                fixture.service.review(
                    9L,
                    new ReviewExpertVerificationRequest(
                        ExpertVerificationStatus.VERIFIED, List.of(999L), null, null)))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ExpertErrorCode.CREDENTIAL_NOT_FOUND));
  }

  private static final class Fixture {
    private final CurrentAuthenticatedUserResolver resolver =
        mock(CurrentAuthenticatedUserResolver.class);
    private final UserRepository userRepository = mock(UserRepository.class);
    private final ExpertProfileRepository profileRepository = mock(ExpertProfileRepository.class);
    private final ExpertCredentialRepository credentialRepository =
        mock(ExpertCredentialRepository.class);
    private final ExpertVerificationAuditRepository auditRepository =
        mock(ExpertVerificationAuditRepository.class);
    private final NotificationRepository notificationRepository =
        mock(NotificationRepository.class);
    private final ExpertVerificationService service;

    private Fixture(UserRole role) {
      User reviewer = mock(User.class);
      given(resolver.requireUserId()).willReturn(7L);
      given(userRepository.findById(7L)).willReturn(Optional.of(reviewer));
      given(reviewer.getRole()).willReturn(role);
      service =
          new ExpertVerificationService(
              resolver,
              userRepository,
              profileRepository,
              credentialRepository,
              auditRepository,
              notificationRepository,
              Clock.fixed(REVIEWED_AT, ZoneOffset.UTC));
    }

    private ExpertProfile profile() {
      ExpertProfile profile =
          ExpertProfile.pending(
              70L,
              null,
              new CreateExpertProfileRequest(
                  "전문가", null, null, 3, List.of("ART_THERAPY"), null, null, null, false, null),
              LocalDateTime.parse("2026-08-01T00:00:00"));
      ReflectionTestUtils.setField(profile, "id", 9L);
      return profile;
    }

    private ExpertCredential credential(ExpertProfile profile, Long credentialId) {
      ExpertCredential credential =
          ExpertCredential.pending(
              profile,
              new UploadExpertCredentialRequest("ART_THERAPIST", "미술심리상담사", "한국상담협회", null, null),
              LocalDateTime.parse("2026-08-02T00:00:00"));
      ReflectionTestUtils.setField(credential, "id", credentialId);
      return credential;
    }

    private com.ssafy.b209.notification.domain.Notification savedNotification() {
      var captor =
          org.mockito.ArgumentCaptor.forClass(
              com.ssafy.b209.notification.domain.Notification.class);
      org.mockito.Mockito.verify(notificationRepository).save(captor.capture());
      return captor.getValue();
    }
  }
}
