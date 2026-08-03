package com.ssafy.b209.database;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import org.junit.jupiter.api.Test;

/** Flyway Migration 버전과 그림 활동 기준 데이터 계약을 파일 수준에서 검증한다. */
class MigrationVersionTest {

  private static final Path MIGRATION_DIRECTORY =
      Path.of("src", "main", "resources", "db", "migration");
  private static final Pattern VERSION_PATTERN = Pattern.compile("^V(\\d+)__.+\\.sql$");

  @Test
  void migrationVersionsAreUnique() throws IOException {
    List<Integer> versions;
    try (var paths = Files.list(MIGRATION_DIRECTORY)) {
      versions =
          paths
              .map(path -> path.getFileName().toString())
              .map(VERSION_PATTERN::matcher)
              .filter(Matcher::matches)
              .map(matcher -> Integer.parseInt(matcher.group(1)))
              .toList();
    }

    assertThat(versions).doesNotHaveDuplicates();
  }

  @Test
  void v12SeedsRequiredDrawingTypesWithoutOverwritingExistingRows() throws IOException {
    Path migration = MIGRATION_DIRECTORY.resolve("V12__seed_drawing_types.sql");

    assertThat(migration).exists();

    String sql = Files.readString(migration, StandardCharsets.UTF_8);
    assertThat(sql)
        .contains("INSERT IGNORE INTO drawing_types")
        .contains("'ART_DIARY'")
        .contains("'FREE_DRAWING'")
        .contains("'EMOTION_COLORING'")
        .contains("'WEATHER_MIND'")
        .contains("guide_text")
        .contains("display_order");
  }

  @Test
  void v29SeedsContentHtmlForEveryConsentTermSeededByV17() throws IOException {
    Path migration = MIGRATION_DIRECTORY.resolve("V29__seed_consent_term_contents.sql");

    assertThat(migration).exists();

    String sql = Files.readString(migration, StandardCharsets.UTF_8);

    // V17 이 심은 7종 모두를 채워야 한다. 하나라도 빠지면 그 약관만 상세가 빈 화면이 된다.
    for (String termCode :
        List.of(
            "SERVICE_TOS",
            "CHILD_PERSONAL_INFO",
            "DRAWING_ANALYSIS",
            "VOICE_PROCESSING",
            "EXPERT_SHARING",
            "AI_TRAINING",
            "MARKETING")) {
      assertThat(sql).contains("WHERE term_code = '" + termCode + "' AND version = 'v1';");
    }

    // 시드 문구를 문단 태그만으로 제한한다. 원래 근거였던 기술적 제약은 이미 해소됐다 —
    // 평문 변환기가 <br>·</p> 만 줄바꿈으로 처리해 <h1>·<ul>·<li> 가 한 줄로 붙던 문제(447 D7)는
    // S15P11B209-782(5f9bf3b4941c5398aef96d7ddb29ed687b4f208a)가 블록 태그 26종을 개행으로
    // 치환하도록 고쳐 사라졌다. 그럼에도 제한을 유지하는 것은 정책적 선택이다: 같은 이용약관이
    // 정적 공표본(infra/nginx/html/legal/terms/index.html)과 이 시드 두 곳에 존재하므로,
    // 양쪽 마크업이 모두 자유로워지면 대조가 어려워진다. 표현의 자유는 정적본에 두고 이쪽은
    // 문단 단위로 단순하게 유지한다(S15P11B209-783, docs/adr/0002-legal-document-source-of-truth.md).
    // 조 번호·제목의 일치 여부는 LegalDocumentConsistencyTest 가 따로 지킨다.
    // 헤더 주석은 이 규칙 자체를 설명하며 태그 이름을 언급하므로, 주석 줄을 걷어낸 SQL 본문만 검사한다.
    String statements =
        sql.lines().filter(line -> !line.startsWith("--")).collect(Collectors.joining("\n"));

    assertThat(statements).doesNotContain("<li>").doesNotContain("<ul>").doesNotContain("<ol>");
    assertThat(statements).doesNotContain("<h1>").doesNotContain("<h2>").doesNotContain("<h3>");
    // 문단은 <p>로 열고 닫아야 평문에서 빈 줄로 분리된다.
    assertThat(statements).contains("<p>").contains("</p>");
  }
}
