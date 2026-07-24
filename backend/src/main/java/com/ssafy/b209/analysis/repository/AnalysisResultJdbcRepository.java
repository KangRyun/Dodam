package com.ssafy.b209.analysis.repository;

import com.ssafy.b209.infrastructure.ai.drawing.contract.AiDrawingAnalysisResponse;
import java.math.BigDecimal;
import java.sql.PreparedStatement;
import java.sql.Statement;
import java.time.LocalDateTime;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.stereotype.Repository;

/**
 * AI 종합 분석 응답의 보조 결과를 정규화된 분석 Table에 저장한다.
 *
 * <p>분석의 상태와 객체 탐지는 JPA Aggregate가 담당하며, 이 Repository는 시각·행동 특징, 대화 요약, 관찰 초안, 근거, 미사용 입력과 경고를 같은
 * Transaction 안에서 교체한다.
 */
@Repository
public class AnalysisResultJdbcRepository {

  private final JdbcTemplate jdbcTemplate;

  /**
   * 분석 보조 결과 저장에 사용할 JDBC 접근자를 주입받는다.
   *
   * @param jdbcTemplate Spring이 관리하는 JDBC 접근자
   */
  public AnalysisResultJdbcRepository(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  /**
   * 분석 식별자에 연결된 기존 보조 결과를 제거하고 정본 응답으로 교체한다.
   *
   * <p>호출 Service의 Transaction에 참여하므로 일부 Table 저장에 실패하면 전체 교체가 Rollback된다.
   *
   * @param analysisId 결과를 소유하는 분석 식별자
   * @param response AI 서버의 검증된 정본 응답
   * @param occurredAt Spring Boot가 응답 처리를 완료한 UTC 시각
   */
  public void replace(
      Long analysisId, AiDrawingAnalysisResponse response, LocalDateTime occurredAt) {
    deleteExisting(analysisId);
    saveModels(analysisId, response.modelInfo());
    saveVisualFeatures(analysisId, response.visualFeatures());
    saveBehaviorFeatures(analysisId, response.behaviorFeatures());
    saveConversationSummary(analysisId, response);
    saveObservationDraft(analysisId, response);
    saveUnusedInputs(analysisId, response, occurredAt);
    saveWarnings(analysisId, response);
    saveEvidenceReferences(analysisId, response);
  }

  private void deleteExisting(Long analysisId) {
    jdbcTemplate.update(
        "DELETE FROM analysis_evidence_reference_authors "
            + "WHERE evidence_reference_id IN "
            + "(SELECT evidence_reference_id FROM analysis_evidence_references "
            + "WHERE analysis_id = ?)",
        analysisId);
    String[] tables = {
      "analysis_evidence_references",
      "analysis_observation_items",
      "analysis_warnings",
      "analysis_model_components",
      "analysis_unused_inputs",
      "analysis_conversation_summaries",
      "analysis_observation_results",
      "analysis_behavior_features",
      "analysis_visual_features"
    };
    for (String table : tables) {
      jdbcTemplate.update("DELETE FROM " + table + " WHERE analysis_id = ?", analysisId);
    }
  }

  private void saveModels(Long analysisId, AiDrawingAnalysisResponse.ModelInfo modelInfo) {
    saveModel(analysisId, "OBJECT_DETECTION", modelInfo.objectDetection(), null);
    saveModel(analysisId, "VISION", modelInfo.vision(), null);
    saveModel(analysisId, "LANGUAGE", modelInfo.language(), null);
    if (modelInfo.knowledgeBaseVersion() != null) {
      saveModel(analysisId, "KNOWLEDGE_BASE", null, modelInfo.knowledgeBaseVersion());
    }
  }

  private void saveModel(
      Long analysisId,
      String componentType,
      AiDrawingAnalysisResponse.ModelRef model,
      String knowledgeBaseVersion) {
    if (model == null && knowledgeBaseVersion == null) {
      return;
    }
    jdbcTemplate.update(
        "INSERT INTO analysis_model_components "
            + "(analysis_id, component_type, model_name, model_version, knowledge_base_version) "
            + "VALUES (?, ?, ?, ?, ?)",
        analysisId,
        componentType,
        model == null ? null : model.name(),
        model == null ? null : model.version(),
        knowledgeBaseVersion);
  }

  private void saveVisualFeatures(Long analysisId, Map<String, Object> features) {
    if (features.isEmpty()) {
      return;
    }
    jdbcTemplate.update(
        "INSERT INTO analysis_visual_features "
            + "(analysis_id, image_width_px, image_height_px, canvas_coverage_ratio, "
            + "average_brightness, average_saturation, average_line_thickness, fill_ratio) "
            + "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        analysisId,
        number(features, "imageWidth"),
        number(features, "imageHeight"),
        decimal(features, "occupancyRatio"),
        decimal(features, "meanBrightness"),
        decimal(features, "meanSaturation"),
        decimal(features, "strokeThickness"),
        decimal(features, "inkRatio"));
  }

  private void saveBehaviorFeatures(Long analysisId, Map<String, Object> features) {
    if (features.isEmpty()) {
      return;
    }
    jdbcTemplate.update(
        "INSERT INTO analysis_behavior_features "
            + "(analysis_id, drawing_duration_ms, active_drawing_duration_ms, pause_count, "
            + "undo_count, erase_count, tool_change_count, color_change_count, "
            + "pressure_available, average_pressure, maximum_pressure) "
            + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        analysisId,
        number(features, "drawingDurationMs"),
        number(features, "activeDrawingMs"),
        number(features, "pauseCount"),
        number(features, "undoCount"),
        number(features, "eraseCount"),
        number(features, "toolChangeCount"),
        number(features, "colorChangeCount"),
        features.get("pressureAvailable"),
        number(features, "pressureMean"),
        number(features, "pressureMax"));
  }

  private void saveConversationSummary(Long analysisId, AiDrawingAnalysisResponse response) {
    AiDrawingAnalysisResponse.ConversationSummary summary = response.conversationSummary();
    if (summary == null) {
      return;
    }
    AiDrawingAnalysisResponse.ModelRef language = response.modelInfo().language();
    jdbcTemplate.update(
        "INSERT INTO analysis_conversation_summaries "
            + "(analysis_id, summary_text, question_count, response_count, "
            + "skipped_question_count, unrecognized_speech_count, representative_utterance, "
            + "summary_model_version) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        analysisId,
        summary.summaryText(),
        summary.questionCount(),
        summary.responseCount(),
        summary.skippedQuestionCount(),
        summary.unrecognizedSpeechCount(),
        summary.representativeUtterance(),
        language == null ? null : language.version());
  }

  private void saveObservationDraft(Long analysisId, AiDrawingAnalysisResponse response) {
    AiDrawingAnalysisResponse.ObservationDraft draft = response.observationDraft();
    if (draft == null) {
      return;
    }
    AiDrawingAnalysisResponse.ModelRef language = response.modelInfo().language();
    String firstFollowUp =
        draft.followUpQuestions().isEmpty() ? null : draft.followUpQuestions().getFirst();
    jdbcTemplate.update(
        "INSERT INTO analysis_observation_results "
            + "(analysis_id, result_version, overall_summary, follow_up_question, "
            + "is_expert_review_required, review_status, disclaimer_text, "
            + "generated_model_version) VALUES (?, 1, ?, ?, ?, ?, ?, ?)",
        analysisId,
        draft.overallSummary(),
        firstFollowUp,
        draft.expertReviewRequired(),
        draft.status(),
        draft.disclaimer(),
        language == null ? null : language.version());
    saveObservationItems(analysisId, "OBSERVATION", draft.observations());
    saveObservationItems(analysisId, "FOLLOW_UP_QUESTION", draft.followUpQuestions());
  }

  private void saveObservationItems(
      Long analysisId, String itemType, java.util.List<String> contents) {
    for (int index = 0; index < contents.size(); index++) {
      jdbcTemplate.update(
          "INSERT INTO analysis_observation_items "
              + "(analysis_id, item_type, item_order, content) VALUES (?, ?, ?, ?)",
          analysisId,
          itemType,
          index,
          contents.get(index));
    }
  }

  private void saveUnusedInputs(
      Long analysisId, AiDrawingAnalysisResponse response, LocalDateTime occurredAt) {
    for (AiDrawingAnalysisResponse.UnusedInput input : response.unusedInputs()) {
      jdbcTemplate.update(
          "INSERT INTO analysis_unused_inputs "
              + "(analysis_id, source_type, excluded_reason_code, excluded_reason_detail, "
              + "retryable, occurred_at) VALUES (?, ?, ?, ?, ?, ?)",
          analysisId,
          input.sourceType(),
          input.reasonCode(),
          input.reasonDetail(),
          input.retryable(),
          occurredAt);
    }
  }

  private void saveWarnings(Long analysisId, AiDrawingAnalysisResponse response) {
    for (int index = 0; index < response.warnings().size(); index++) {
      jdbcTemplate.update(
          "INSERT INTO analysis_warnings (analysis_id, warning_order, warning_code) "
              + "VALUES (?, ?, ?)",
          analysisId,
          index,
          response.warnings().get(index));
    }
  }

  private void saveEvidenceReferences(Long analysisId, AiDrawingAnalysisResponse response) {
    for (int index = 0; index < response.evidenceReferences().size(); index++) {
      AiDrawingAnalysisResponse.EvidenceReference evidence =
          response.evidenceReferences().get(index);
      GeneratedKeyHolder keyHolder = new GeneratedKeyHolder();
      int order = index;
      jdbcTemplate.update(
          connection -> {
            PreparedStatement statement =
                connection.prepareStatement(
                    "INSERT INTO analysis_evidence_references "
                        + "(analysis_id, reference_order, source_id, title, published_year, "
                        + "section_name, evidence_type, applicability, limitations, "
                        + "knowledge_base_version, retrieved_chunk_hash) "
                        + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    Statement.RETURN_GENERATED_KEYS);
            statement.setLong(1, analysisId);
            statement.setInt(2, order);
            statement.setString(3, evidence.sourceId());
            statement.setString(4, evidence.title());
            if (evidence.publishedYear() == null) {
              statement.setNull(5, java.sql.Types.INTEGER);
            } else {
              statement.setInt(5, evidence.publishedYear());
            }
            statement.setString(6, evidence.section());
            statement.setString(7, evidence.evidenceType());
            statement.setString(8, evidence.applicability());
            statement.setString(9, evidence.limitations());
            statement.setString(10, evidence.knowledgeBaseVersion());
            statement.setString(11, evidence.retrievedChunkHash());
            return statement;
          },
          keyHolder);
      Number key = keyHolder.getKey();
      if (key == null) {
        throw new IllegalStateException("evidence reference key was not generated");
      }
      for (int authorOrder = 0; authorOrder < evidence.authors().size(); authorOrder++) {
        jdbcTemplate.update(
            "INSERT INTO analysis_evidence_reference_authors "
                + "(evidence_reference_id, author_order, author_name) VALUES (?, ?, ?)",
            key.longValue(),
            authorOrder,
            evidence.authors().get(authorOrder));
      }
    }
  }

  private Number number(Map<String, Object> features, String key) {
    Object value = features.get(key);
    return value instanceof Number number ? number : null;
  }

  private BigDecimal decimal(Map<String, Object> features, String key) {
    Number number = number(features, key);
    return number == null ? null : new BigDecimal(number.toString());
  }
}
