package com.ssafy.b209.storage.deletion;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.then;
import static org.mockito.Mockito.verifyNoInteractions;

import com.ssafy.b209.storage.audio.AudioStorage;
import com.ssafy.b209.storage.image.ImageStorage;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 유형별 라우팅 검증 (S15P11B209-780).
 *
 * <p>그림과 음성은 같은 버킷에 프리픽스로만 갈리므로, 잘못된 저장소를 부르면 엉뚱한 경로를 지우고도 성공으로 보고된다. 그래서 "어느 저장소를 불렀는가"를 유형마다 못
 * 박는다.
 */
@ExtendWith(MockitoExtension.class)
class StorageDeletionRouterTest {

  @Mock private ImageStorage imageStorage;
  @Mock private AudioStorage audioStorage;
  @InjectMocks private StorageDeletionRouter router;

  private static StorageDeletionJob job(String resourceType) {
    return new StorageDeletionJob(1L, "2026/08/key.bin", resourceType, 0);
  }

  @Test
  @DisplayName("그림 자산은 이미지 저장소로 간다")
  void routesDrawingAssetToImageStorage() {
    router.delete(job("DRAWING_ASSET"));

    then(imageStorage).should().delete("2026/08/key.bin");
    verifyNoInteractions(audioStorage);
  }

  @Test
  @DisplayName("아동 프로필 이미지는 이미지 저장소로 간다")
  void routesChildProfileImageToImageStorage() {
    router.delete(job("CHILD_PROFILE_IMAGE"));

    then(imageStorage).should().delete("2026/08/key.bin");
    verifyNoInteractions(audioStorage);
  }

  @Test
  @DisplayName("커뮤니티 첨부는 이미지 저장소로 간다")
  void routesCommunityAttachmentToImageStorage() {
    router.delete(job("COMMUNITY_ATTACHMENT"));

    then(imageStorage).should().delete("2026/08/key.bin");
    verifyNoInteractions(audioStorage);
  }

  @Test
  @DisplayName("대화 음성은 음성 저장소로 간다 — 이미지 저장소를 부르면 다른 프리픽스를 지운다")
  void routesConversationAudioToAudioStorage() {
    router.delete(job("CONVERSATION_AUDIO"));

    then(audioStorage).should().delete("2026/08/key.bin");
    verifyNoInteractions(imageStorage);
  }

  @Test
  @DisplayName("매핑 없는 유형은 어느 저장소도 부르지 않고 예외를 던진다")
  void rejectsUnmappedResourceType() {
    // REPORT_PDF 는 저장 위치가 미정이라 의도적으로 매핑하지 않았다.
    // 추측해서 이미지 저장소로 보내면 S3 가 없는 키에도 성공을 돌려줘 "거짓 COMPLETED" 가 된다.
    assertThatThrownBy(() -> router.delete(job("REPORT_PDF")))
        .isInstanceOf(StorageDeletionRouter.UnmappedResourceTypeException.class);

    verifyNoInteractions(imageStorage, audioStorage);
  }

  @Test
  @DisplayName("알 수 없는 유형도 조용히 넘어가지 않는다")
  void rejectsUnknownResourceType() {
    assertThatThrownBy(() -> router.delete(job("SOMETHING_NEW")))
        .isInstanceOf(StorageDeletionRouter.UnmappedResourceTypeException.class);

    verifyNoInteractions(imageStorage, audioStorage);
  }
}
