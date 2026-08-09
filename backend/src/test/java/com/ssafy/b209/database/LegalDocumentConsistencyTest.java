package com.ssafy.b209.database;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.fail;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.IntStream;
import org.junit.jupiter.api.Test;

/**
 * 서비스 이용약관의 두 사본이 갈라지지 않았는지 파일 수준에서 검증한다.
 *
 * <p>같은 약관이 두 곳에 있다. 의미의 정본은 DB 쪽이고(동의 증빙 {@code consent_records.consent_term_id} 가 그 문구를 가리킨다), 정적
 * HTML 은 대외 공표용 사본이다. 개정할 때 한쪽만 고치면 앱 사용자와 웹 방문자가 서로 다른 약관을 보게 된다 (S15P11B209-783 — 실제로 정적 12조 / DB
 * 13조로 갈라진 상태가 발견됐다).
 *
 * <ul>
 *   <li>정적: {@code infra/nginx/html/legal/terms/index.html}
 *   <li>DB: {@code backend/src/main/resources/db/migration/V29__seed_consent_term_contents.sql} 의
 *       {@code SERVICE_TOS} 블록
 * </ul>
 *
 * <p>본문 전문은 비교하지 않는다. 두 사본은 마크업 문법이 다르고(정적은 {@code <h2>}/{@code <ol>}, DB 는 {@code <p>}/{@code
 * <br>}) 문장 다듬기의 자유도 다르다. 대신 <b>조 번호와 조 제목의 목록</b>이 정확히 같은지만 본다 — 조가 늘거나 빠지거나 제목이 바뀌는 것이 이 이슈에서 실제로
 * 일어난 드리프트 형태이고, 상호 참조("제10조에 따라")가 어긋나는 원인이기 때문이다.
 *
 * <p>Docker·Testcontainers 를 쓰지 않는 순수 파일 테스트다. 두 파일을 읽기만 한다.
 */
class LegalDocumentConsistencyTest {

  /** 정적 공표본. 리포 루트 기준 경로. */
  private static final String STATIC_TERMS_RELATIVE_PATH =
      "infra/nginx/html/legal/terms/index.html";

  /** 의미의 정본이 들어 있는 마이그레이션. 리포 루트 기준 경로. */
  private static final String MIGRATION_RELATIVE_PATH =
      "backend/src/main/resources/db/migration/V29__seed_consent_term_contents.sql";

  /** {@code SERVICE_TOS} UPDATE 문의 끝. 이 앞까지가 이용약관 본문이다. */
  private static final String SERVICE_TOS_STATEMENT_END =
      "WHERE term_code = 'SERVICE_TOS' AND version = 'v1';";

  /**
   * 조 하나의 시작 부분. 여는 태그가 무엇이든 "제N조 (제목)" 이라는 텍스트는 두 사본에 공통이다.
   *
   * <p>공백과 괄호 표기의 흔들림을 관용한다. 공백을 필수 1칸으로 두면 {@code 제14조(준거법)} 처럼 붙여 쓴 조가 정규식에 걸리지 않아 <b>검증 대상에서 조용히
   * 사라진다</b> — 새 조를 붙이는 사람이 공백을 빼는 순간 그 조는 영원히 대조되지 않는다(783 QA M-1 실측). 반각/전각 괄호, 반각 공백과 전각
   * 공백(U+3000)을 모두 받는다. 자바 {@code \s} 에는 U+3000 이 포함되지 않으므로 직접 넣는다.
   */
  private static final Pattern ARTICLE_PATTERN =
      Pattern.compile("제(\\d+)조[\\s\\u3000]*[(（]([^()（）]+)[)）]");

  /**
   * 이용약관의 조 개수. 조를 늘리거나 줄이면 <b>이 값도 함께 고쳐야</b> 한다.
   *
   * <p>번호 연속성만으로는 <b>양쪽 사본이 동시에 마지막 조를 잃는</b> 형태를 잡지 못한다. {@code {1..12}} 는 그 자체로 연속이라 통과해 버린다. 개수를
   * 못 박아 두면 조가 사라지는 변경이 반드시 이 상수를 손대게 만들어, 의도한 개정과 사고를 구분할 수 있다.
   */
  private static final int EXPECTED_ARTICLE_COUNT = 13;

  @Test
  void staticTermsPageAndSeededServiceTosDeclareTheSameArticles() throws IOException {
    Path repositoryRoot = locateRepositoryRoot();

    Path staticTerms = repositoryRoot.resolve(STATIC_TERMS_RELATIVE_PATH);
    Path migration = repositoryRoot.resolve(MIGRATION_RELATIVE_PATH);
    // 경로가 어긋나면 조 목록이 양쪽 다 비어 "일치"로 통과해 버린다. 그래서 존재부터 단언한다.
    assertThat(staticTerms).exists().isRegularFile();
    assertThat(migration).exists().isRegularFile();

    Map<Integer, String> staticArticles =
        extractArticles(Files.readString(staticTerms, StandardCharsets.UTF_8));
    Map<Integer, String> seededArticles =
        extractArticles(
            extractServiceTosBlock(Files.readString(migration, StandardCharsets.UTF_8)));

    // 어느 한쪽이라도 비면 파싱이 깨진 것이다. 빈 집합끼리의 일치를 성공으로 읽지 않는다.
    assertThat(staticArticles).as("정적 이용약관에서 추출한 조").isNotEmpty();
    assertThat(seededArticles).as("V29 SERVICE_TOS 에서 추출한 조").isNotEmpty();

    assertThat(staticArticles)
        .as(
            "이용약관 두 사본의 조 번호·제목이 다르다. 한쪽만 개정하면 앱과 웹이 서로 다른 약관을 보여준다."
                + " 정본은 %s 이고 %s 를 맞춰야 한다(docs/adr/0002-legal-document-source-of-truth.md).",
            MIGRATION_RELATIVE_PATH, STATIC_TERMS_RELATIVE_PATH)
        .containsExactlyInAnyOrderEntriesOf(seededArticles);

    // 조 번호는 1부터 가장 큰 번호까지 빠짐없이 이어져야 한다. 개수(size)가 아니라 실제 번호의
    // 최댓값을 기준으로 본다 — size 기준이면 중간이 빠지고 뒤가 밀려도 우연히 맞아떨어진다.
    int highestNumber =
        seededArticles.keySet().stream().mapToInt(Integer::intValue).max().orElse(0);
    assertThat(seededArticles.keySet())
        .as("조 번호가 1..%d 로 연속되지 않는다(빠진 번호가 있다)", highestNumber)
        .containsExactlyInAnyOrderElementsOf(
            IntStream.rangeClosed(1, highestNumber).boxed().toList());

    // 양쪽이 동시에 마지막 조를 잃으면 위 연속성 단언은 통과한다. 개수를 못 박아 그 구멍을 막는다.
    assertThat(seededArticles)
        .as(
            "이용약관 조 개수가 %d 가 아니다. 의도한 개정이면 EXPECTED_ARTICLE_COUNT 도 함께 고쳐라.",
            EXPECTED_ARTICLE_COUNT)
        .hasSize(EXPECTED_ARTICLE_COUNT);
  }

  /**
   * {@code 제N조 (제목)} 을 모두 뽑아 번호 → 제목으로 만든다.
   *
   * @param document 약관 사본 원문(HTML 또는 SQL)
   * @return 조 번호와 조 제목. 같은 번호가 두 번 나오면 실패로 처리한다
   */
  private Map<Integer, String> extractArticles(String document) {
    Map<Integer, String> articles = new LinkedHashMap<>();
    Matcher matcher = ARTICLE_PATTERN.matcher(document);
    while (matcher.find()) {
      int number = Integer.parseInt(matcher.group(1));
      String title = matcher.group(2).trim();
      String previous = articles.put(number, title);
      if (previous != null && !previous.equals(title)) {
        fail("같은 문서 안에서 제%d조의 제목이 둘이다: '%s' vs '%s'".formatted(number, previous, title));
      }
    }
    return articles;
  }

  /**
   * 마이그레이션에서 {@code SERVICE_TOS} 의 {@code content_html} 만 잘라낸다.
   *
   * <p>파일에는 UPDATE 문이 7개 있고 다른 약관에도 번호 매긴 항목이 있다. 이용약관 블록만 봐야 다른 약관의 문구가 조 목록에 섞이지 않는다. 파일 앞머리의 주석은
   * {@code 제N조} 표기를 쓰지 않지만, 블록을 좁히면 주석까지 자연히 배제된다.
   *
   * @param migrationSql V29 마이그레이션 전문
   * @return {@code SERVICE_TOS} 의 본문 HTML
   */
  private String extractServiceTosBlock(String migrationSql) {
    int statementEnd = migrationSql.indexOf(SERVICE_TOS_STATEMENT_END);
    if (statementEnd < 0) {
      fail("V29 에서 SERVICE_TOS UPDATE 문을 찾지 못했다. 약관 정본 위치가 바뀌었다면 이 테스트도 함께 고쳐야 한다.");
    }
    int contentStart = migrationSql.lastIndexOf("SET content_html = '", statementEnd);
    if (contentStart < 0) {
      fail("SERVICE_TOS UPDATE 문에서 content_html 대입을 찾지 못했다.");
    }
    return migrationSql.substring(contentStart, statementEnd);
  }

  /**
   * {@code backend} 와 {@code infra} 를 함께 가진 디렉터리를 위로 올라가며 찾는다.
   *
   * <p>Gradle 은 테스트 작업 디렉터리를 {@code backend} 로 두지만(그래서 {@code MigrationVersionTest} 의 상대 경로가 통한다),
   * 리포 루트에서 실행되는 경우도 성립하도록 고정 {@code ../} 대신 위로 탐색한다. 못 찾으면 조용히 넘어가지 않고 실패한다 — 경로가 깨진 테스트는 통과해도
   * 아무것도 지켜 주지 않는다.
   *
   * @return 리포지터리 루트 절대 경로
   */
  private Path locateRepositoryRoot() {
    Path start = Path.of("").toAbsolutePath();
    for (Path candidate = start; candidate != null; candidate = candidate.getParent()) {
      if (Files.isDirectory(candidate.resolve("backend"))
          && Files.isDirectory(candidate.resolve("infra"))) {
        return candidate;
      }
    }
    return fail(
        ("작업 디렉터리 %s 위쪽에서 backend/ 와 infra/ 를 함께 가진 리포지터리 루트를 찾지 못했다."
                + " 정적 약관 파일을 읽을 수 없으므로 검증을 건너뛰지 않고 실패시킨다.")
            .formatted(start));
  }
}
