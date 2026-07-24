package com.ssafy.b209.database;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
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
}
