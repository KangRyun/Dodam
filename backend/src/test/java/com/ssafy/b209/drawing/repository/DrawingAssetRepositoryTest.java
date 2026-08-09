package com.ssafy.b209.drawing.repository;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.domain.ChildFixture;
import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.child.repository.ChildRepository;
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.domain.DrawingTypeFixture;
import com.ssafy.b209.drawing.domain.DrawingTypeSelectableBy;
import jakarta.persistence.EntityManager;
import java.time.LocalDate;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;

@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
class DrawingAssetRepositoryTest {

  @Autowired private EntityManager entityManager;
  @Autowired private ChildRepository childRepository;
  @Autowired private DrawingTypeRepository drawingTypeRepository;
  @Autowired private DrawingSessionRepository drawingSessionRepository;
  @Autowired private DrawingAssetRepository drawingAssetRepository;

  @Test
  void findsLatestDraftByAssetVersionWithinSession() {
    DrawingSession firstSession = saveSession("draft-session-1");
    DrawingSession secondSession = saveSession("draft-session-2");
    saveDraft(firstSession, 1, 10);
    DrawingAsset latest = saveDraft(firstSession, 2, 20);
    saveDraft(secondSession, 3, 30);

    entityManager.flush();
    entityManager.clear();

    assertThat(drawingAssetRepository.findLatestDraft(firstSession.getId()))
        .hasValueSatisfying(
            asset -> {
              assertThat(asset.getId()).isEqualTo(latest.getId());
              assertThat(asset.getWidthPx()).isEqualTo(1280);
              assertThat(asset.getHeightPx()).isEqualTo(720);
            });
  }

  private DrawingSession saveSession(String idempotencyKey) {
    Child child =
        childRepository.save(
            ChildFixture.create(
                null,
                LocalDate.of(2018, 7, 21),
                ChildTutorialStatus.NOT_STARTED,
                ChildProfileStatus.ACTIVE,
                null));
    DrawingType drawingType =
        drawingTypeRepository.save(
            DrawingTypeFixture.create(
                null,
                "HOUSE-" + idempotencyKey,
                "House",
                DrawingTypeSelectableBy.BOTH,
                6,
                10,
                true));
    return drawingSessionRepository.save(
        DrawingSession.start(
            child,
            drawingType,
            DrawingInputMethod.CANVAS,
            LocalDateTime.of(2026, 7, 22, 1, 0),
            idempotencyKey));
  }

  private DrawingAsset saveDraft(DrawingSession session, int version, long lastEventSequence) {
    return drawingAssetRepository.save(
        DrawingAsset.draft(
            session,
            version,
            "drafts/" + session.getId() + "/" + version + ".png",
            "image/png",
            100,
            1280,
            720,
            "a".repeat(64),
            lastEventSequence,
            LocalDateTime.of(2026, 7, 22, 1, version),
            LocalDateTime.of(2026, 7, 22, 1, version)));
  }
}
