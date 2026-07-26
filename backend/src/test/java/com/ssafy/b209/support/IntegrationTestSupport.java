package com.ssafy.b209.support;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.StringJoiner;
import org.junit.jupiter.api.BeforeEach;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.MySQLContainer;

/**
 * MySQL Testcontainer를 JVM당 1개만 띄워 공유하는 통합테스트 베이스 (S15P11B209-391 Phase 3).
 *
 * <p><b>왜:</b> 이전에는 통합테스트 클래스마다 {@code @Container}로 각자 컨테이너를 띄웠다. Jenkins 빌드 #140 실측에서 {@code
 * :test} 654초 중 실제 테스트 실행은 59초(9%)뿐이고, 나머지 595초가 컨테이너 14개 기동 + Flyway 전체 Migration 반복 + Spring
 * Context 재부팅 비용이었다. 컨테이너 주소가 클래스마다 달라 Spring TestContext 캐시도 매번 미스났다.
 *
 * <p><b>수명주기:</b> {@code @Container}(JUnit Testcontainers Extension)를 쓰지 않는다. 그 확장은 컨테이너를 <i>클래스
 * 단위</i>로 시작·종료하므로 JVM singleton이라는 목적과 어긋난다. 아래 static 초기화로 한 번만 시작하고, 종료는 Testcontainers의 Ryuk
 * 사이드카가 JVM 종료 후 정리하도록 맡긴다.
 *
 * <p><b>격리:</b> 컨테이너를 공유하므로 클래스 간 데이터가 새는 것을 막아야 한다. 매 테스트 전에 더럽혀진 테이블만 TRUNCATE 한다(자세한 규칙과 성능
 * 근거는 {@link #truncateSharedDatabase()} 참고). 실행 순서에 의존하지 않으므로 {@code ./gradlew test -PrandomTestOrder}로
 * 클래스 순서를 섞어도 통과한다.
 *
 * <p><b>⚠️ 병렬 실행 금지:</b> 이 격리 방식은 같은 JVM 안에서의 클래스 병렬 실행과 양립할 수 없다(서로의 데이터를 지운다). {@code
 * src/test/resources/junit-platform.properties}에서 병렬 실행을 명시적으로 끈다. 병렬화가 필요해지면 컨테이너를 fork당 1개로 두는
 * {@code maxParallelForks} 방식을 검토할 것.
 *
 * <p><b>이 베이스를 쓰지 않는 통합테스트(의도적 예외):</b>
 *
 * <ul>
 *   <li>{@code DatabaseMigrationSafetyIntegrationTest} — {@code flyway().clean()} 후 부분 Migration을
 *       반복하므로 스키마 자체를 흔든다
 *   <li>{@code DatabaseMigrationIntegrationTest} — 정리 없이 전역 COUNT를 단언한다(깨끗한 DB 전제)
 *   <li>{@code MvpMockDataIntegrationTest} — 비-Spring, 자체 Flyway Migration을 수행한다
 * </ul>
 */
@SpringBootTest
@ActiveProfiles("integration-test")
public abstract class IntegrationTestSupport {

  /** Flyway가 관리하므로 비우면 안 되는 테이블. */
  private static final String SCHEMA_HISTORY_TABLE = "flyway_schema_history";

  protected static final MySQLContainer<?> MYSQL_CONTAINER =
      new MySQLContainer<>("mysql:8.4.10")
          .withDatabaseName("dodam")
          .withUsername("test")
          .withPassword("test");

  static {
    // JVM당 1회. @Container를 쓰지 않으므로 JUnit이 클래스마다 재시작하지 않는다.
    MYSQL_CONTAINER.start();
  }

  /** information_schema 조회는 한 번이면 충분하다(스키마는 Migration 이후 불변). */
  private static volatile List<String> truncatableTables;

  /** 위 목록으로 조립한 "행이 남아 있는 테이블" 조회 SQL. 매번 만들 필요가 없다. */
  private static volatile String rowPresenceQuery;

  @Autowired private JdbcTemplate jdbcTemplate;

  @DynamicPropertySource
  static void datasourceProperties(DynamicPropertyRegistry registry) {
    registry.add("spring.datasource.url", MYSQL_CONTAINER::getJdbcUrl);
    registry.add("spring.datasource.username", MYSQL_CONTAINER::getUsername);
    registry.add("spring.datasource.password", MYSQL_CONTAINER::getPassword);
    registry.add("spring.datasource.driver-class-name", MYSQL_CONTAINER::getDriverClassName);
  }

  /**
   * 매 테스트 전에 더럽혀진 테이블만 비운다.
   *
   * <p>테이블 목록을 information_schema에서 실행 시점에 읽으므로, 새 테이블이 Migration으로 추가돼도 정리 목록을 손볼 필요가 없다(하드코딩한 FK
   * 역순 목록이 시간이 지나며 뒤처지는 문제를 피한다).
   *
   * <p><b>왜 전체가 아니라 "더럽혀진 것만"인가:</b> 첫 구현은 매 테스트마다 62개 테이블을 전부 TRUNCATE 했는데, 실측에서 테스트 1건당 4.3초가
   * 고정으로 붙었다(통합테스트 39건 × 4.3초 ≈ 168초). InnoDB의 TRUNCATE는 DDL이라 빈 테이블이어도 테이블스페이스를 drop/recreate 하며 약
   * 69ms가 든다. 대부분의 테스트는 5~10개 테이블만 건드리므로, 건드린 것만 골라내면 이 비용이 1/6 이하로 줄어든다.
   *
   * <p><b>DELETE가 아니라 TRUNCATE인 이유:</b> AUTO_INCREMENT 카운터까지 되돌리기 위해서다. 클래스마다 새 컨테이너를 쓰던 시절의 "생성
   * ID가 1부터 시작한다"는 전제에 의존하는 단언이 있다(예: ChildRegistrationIntegrationTest의 {@code childId == 1}).
   *
   * <p><b>순서 의존:</b> {@code FOREIGN_KEY_CHECKS}를 잠시 꺼서 삭제 순서 자체를 무의미하게 만든다. 반드시 같은 커넥션에서 껐다 켜야
   * 하므로({@code SET}은 세션 변수, JdbcTemplate은 호출마다 풀에서 다른 커넥션을 받을 수 있다) {@link ConnectionCallback}으로
   * 커넥션 하나를 붙잡는다. 켜는 것은 finally에서 — 중간에 실패했을 때 FK 검사가 꺼진 커넥션이 풀로 돌아가면 이후 테스트가 조용히 오염된다.
   */
  @BeforeEach
  void truncateSharedDatabase() {
    jdbcTemplate.execute(
        (ConnectionCallback<Void>)
            connection -> {
              List<String> dirty = dirtyTables(connection);
              if (dirty.isEmpty()) {
                return null;
              }
              try (Statement statement = connection.createStatement()) {
                statement.execute("SET FOREIGN_KEY_CHECKS = 0");
                try {
                  for (String table : dirty) {
                    statement.addBatch("TRUNCATE TABLE `" + table + "`");
                  }
                  statement.executeBatch();
                } finally {
                  statement.execute("SET FOREIGN_KEY_CHECKS = 1");
                }
              }
              return null;
            });
  }

  /**
   * 비워야 할 테이블 = 행이 남아 있는 테이블 ∪ AUTO_INCREMENT가 진행된 테이블.
   *
   * <p>두 번째 조건이 필요한 이유: 테스트가 스스로 DELETE 했거나 ON DELETE CASCADE로 행이 사라진 테이블은 "비어 있지만 카운터는 올라간" 상태가
   * 된다. 이걸 놓치면 다음 테스트에서 생성 ID가 1로 시작하지 않는다.
   *
   * <p>행 존재 여부는 테이블 수만큼의 왕복 대신 {@code UNION ALL ... WHERE EXISTS} 한 방으로 확인한다. 빈 InnoDB 테이블의 EXISTS는
   * 첫 행에서 즉시 끝나므로 사실상 공짜다.
   */
  private static List<String> dirtyTables(Connection connection) throws SQLException {
    Set<String> dirty = new LinkedHashSet<>();
    try (Statement statement = connection.createStatement();
        ResultSet resultSet = statement.executeQuery(rowPresenceQuery(connection))) {
      while (resultSet.next()) {
        dirty.add(resultSet.getString(1));
      }
    }
    try (Statement statement = connection.createStatement();
        ResultSet resultSet =
            statement.executeQuery(
                "SELECT table_name FROM information_schema.tables "
                    + "WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE' "
                    + "AND table_name <> '"
                    + SCHEMA_HISTORY_TABLE
                    + "' AND auto_increment > 1")) {
      while (resultSet.next()) {
        dirty.add(resultSet.getString(1));
      }
    }
    return List.copyOf(dirty);
  }

  private static String rowPresenceQuery(Connection connection) throws SQLException {
    String cached = rowPresenceQuery;
    if (cached != null) {
      return cached;
    }
    StringJoiner joiner = new StringJoiner(" UNION ALL ");
    for (String table : truncatableTables(connection)) {
      joiner.add("SELECT '" + table + "' WHERE EXISTS (SELECT 1 FROM `" + table + "`)");
    }
    String built = joiner.toString();
    rowPresenceQuery = built;
    return built;
  }

  private static List<String> truncatableTables(Connection connection) throws SQLException {
    List<String> cached = truncatableTables;
    if (cached != null) {
      return cached;
    }
    List<String> tables = new ArrayList<>();
    try (Statement statement = connection.createStatement();
        ResultSet resultSet =
            statement.executeQuery(
                "SELECT table_name FROM information_schema.tables "
                    + "WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE' "
                    + "AND table_name <> '"
                    + SCHEMA_HISTORY_TABLE
                    + "'")) {
      while (resultSet.next()) {
        tables.add(resultSet.getString(1));
      }
    }
    List<String> discovered = List.copyOf(tables);
    truncatableTables = discovered;
    return discovered;
  }
}
