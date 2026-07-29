package com.ssafy.b209.drawing.htp.repository;

import com.ssafy.b209.drawing.htp.domain.HtpAssessment;
import com.ssafy.b209.drawing.htp.domain.HtpAssessmentStep;
import jakarta.persistence.LockModeType;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** HTP 묶음과 단계·그림 세션 연결을 함께 조회하는 저장소다. */
public interface HtpAssessmentRepository extends JpaRepository<HtpAssessment, Long> {

  /**
   * 그림 세션에 연결된 HTP 단계를 조회한다.
   *
   * @param drawingSessionId 그림 세션 식별자
   * @return 연결된 단계, 일반 활동 세션이거나 잘못된 연결이면 빈 값
   */
  @Query(
      "select step from HtpAssessmentStep step "
          + "where step.drawingSession.id = :drawingSessionId")
  Optional<HtpAssessmentStep> findStepByDrawingSessionId(
      @Param("drawingSessionId") Long drawingSessionId);

  /**
   * 리포트 생성 결과와 HTP 묶음 상태를 같은 Transaction에서 변경하도록 세션 기준 쓰기 잠금 조회한다.
   *
   * @param drawingSessionId HTP 단계 그림 세션 식별자
   * @return 해당 단계를 포함한 HTP 활동, 일반 그림 세션이면 빈 값
   */
  @Lock(LockModeType.PESSIMISTIC_WRITE)
  @Query(
      "select distinct assessment from HtpAssessment assessment "
          + "join fetch assessment.steps step "
          + "join fetch step.drawingSession "
          + "where step.drawingSession.id = :drawingSessionId")
  Optional<HtpAssessment> findByStepDrawingSessionIdForUpdate(
      @Param("drawingSessionId") Long drawingSessionId);

  /**
   * 시작 요청의 멱등 키로 기존 HTP 활동을 조회한다.
   *
   * @param idempotencyKey HTP 시작 요청의 {@code Idempotency-Key}
   * @return 같은 키로 생성된 활동, 없으면 빈 값
   */
  Optional<HtpAssessment> findByIdempotencyKey(String idempotencyKey);

  /**
   * 동시 시작 요청을 재확인하도록 멱등 키의 HTP 활동과 첫 단계를 쓰기 잠금으로 조회한다.
   *
   * @param idempotencyKey HTP 시작 요청의 {@code Idempotency-Key}
   * @return 같은 키로 먼저 생성된 활동, 없으면 빈 값
   */
  @Lock(LockModeType.PESSIMISTIC_WRITE)
  @Query(
      "select distinct assessment from HtpAssessment assessment "
          + "join fetch assessment.steps step "
          + "join fetch step.drawingSession "
          + "where assessment.idempotencyKey = :idempotencyKey")
  Optional<HtpAssessment> findByIdempotencyKeyForUpdate(
      @Param("idempotencyKey") String idempotencyKey);

  /**
   * 아동의 진행 중 HTP 활동과 생성된 단계를 쓰기 잠금으로 조회한다.
   *
   * @param childId HTP 활동을 수행하는 아동 식별자
   * @return 진행 중 HTP 활동, 없으면 빈 값
   */
  @Lock(LockModeType.PESSIMISTIC_WRITE)
  @Query(
      "select distinct assessment from HtpAssessment assessment "
          + "join fetch assessment.steps step "
          + "join fetch step.drawingSession "
          + "where assessment.child.id = :childId "
          + "and assessment.status in ("
          + "com.ssafy.b209.drawing.htp.domain.HtpAssessmentStatus.IN_PROGRESS, "
          + "com.ssafy.b209.drawing.htp.domain.HtpAssessmentStatus.ANALYZING)")
  Optional<HtpAssessment> findActiveByChildIdForUpdate(@Param("childId") Long childId);

  /**
   * 화면 재개에 사용할 아동의 진행 중 HTP 활동과 모든 단계를 조회한다.
   *
   * <p>PERSON 대화가 끝난 직후에는 현재 Drawing Session이 이미 완료 상태이므로 일반 활성 세션 조회만으로는 감정 단계에 복귀할 수 없다.
   *
   * @param childId HTP 활동을 수행하는 아동 식별자
   * @return 진행 또는 분석 중인 HTP 활동, 없으면 빈 값
   */
  @Query(
      "select distinct assessment from HtpAssessment assessment "
          + "join fetch assessment.steps step "
          + "join fetch step.drawingSession "
          + "where assessment.child.id = :childId "
          + "and assessment.status in ("
          + "com.ssafy.b209.drawing.htp.domain.HtpAssessmentStatus.IN_PROGRESS, "
          + "com.ssafy.b209.drawing.htp.domain.HtpAssessmentStatus.ANALYZING)")
  Optional<HtpAssessment> findActiveByChildId(@Param("childId") Long childId);

  /**
   * 접근 검증과 응답 조립에 필요한 아동·유형·단계·그림 세션을 함께 조회한다.
   *
   * @param id HTP 활동 식별자
   * @return 상세 조회 결과, 없으면 빈 값
   */
  @Query(
      "select distinct assessment from HtpAssessment assessment "
          + "join fetch assessment.child "
          + "join fetch assessment.drawingType "
          + "join fetch assessment.steps step "
          + "join fetch step.drawingSession "
          + "where assessment.id = :id")
  Optional<HtpAssessment> findDetailById(@Param("id") Long id);

  /**
   * 상태 전이할 HTP 활동과 모든 단계를 쓰기 잠금으로 조회한다.
   *
   * @param id HTP 활동 식별자
   * @return 잠긴 HTP 활동, 없으면 빈 값
   */
  @Lock(LockModeType.PESSIMISTIC_WRITE)
  @Query(
      "select distinct assessment from HtpAssessment assessment "
          + "join fetch assessment.child "
          + "join fetch assessment.drawingType "
          + "join fetch assessment.steps step "
          + "join fetch step.drawingSession "
          + "where assessment.id = :id")
  Optional<HtpAssessment> findDetailByIdForUpdate(@Param("id") Long id);
}
