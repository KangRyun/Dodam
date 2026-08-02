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

    // 앱이 태그를 벗겨 평문으로 보여주는데 <br>·</p> 만 줄바꿈이 된다. 그 외 블록 태그를 쓰면
    // 평문에서 제목과 본문이 붙어버린다(447 D7). 헤더 주석은 그 규칙 자체를 설명하며 태그 이름을
    // 언급하므로, 주석 줄을 걷어낸 실제 SQL 본문만 검사한다.
    String statements =
        sql.lines().filter(line -> !line.startsWith("--")).collect(Collectors.joining("\n"));

    assertThat(statements).doesNotContain("<li>").doesNotContain("<ul>").doesNotContain("<ol>");
    assertThat(statements).doesNotContain("<h1>").doesNotContain("<h2>").doesNotContain("<h3>");
    // 문단은 <p>로 열고 닫아야 평문에서 빈 줄로 분리된다.
    assertThat(statements).contains("<p>").contains("</p>");
  }
}
