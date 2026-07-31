package com.ssafy.b209.support;

import static org.springframework.data.domain.Sort.Direction.ASC;

import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.index.Index;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.testcontainers.containers.MongoDBContainer;
import org.testcontainers.utility.DockerImageName;

/**
 * 그리기 과정 데이터(스트로크) 저장소 Testcontainer를 JVM당 1개만 공유한다 (S15P11B209-365).
 *
 * <p><b>왜 별도 클래스인가</b>: 통합테스트에는 {@link IntegrationTestSupport} 를 상속하는 것과, 각자 컨테이너를 들고 도는 예외 클래스 (예:
 * {@code MvpFlowIntegrationTest}·{@code UserAccountAndConsentIntegrationTest})가 섞여 있다. 상속에 묶어 두면
 * 후자가 Mongo 를 못 받는다 — 실제로 그래서 스트로크 저장과 탈퇴 경로가 깨졌다. 컨테이너를 상속에서 떼어내 어느 쪽에서든 같은 1개를 쓰게 한다.
 *
 * <p>인증은 걸지 않는다. 운영의 최소권한 계정 분리는 인프라의 관심사이고, 테스트가 검증할 것은 문서 저장·멱등·TTL 계산이다.
 */
public final class SharedMongoContainer {

  /** 운영 initdb 가 만드는 Stroke 멱등 인덱스 이름. */
  private static final String STROKE_UNIQUE = "session_batch_unique";

  private static final MongoDBContainer CONTAINER =
      new MongoDBContainer(DockerImageName.parse("mongo:8.0.4"));

  private static volatile boolean indexesCreated;

  static {
    // JVM당 1회. 종료는 Testcontainers 의 Ryuk 사이드카에 맡긴다(MySQL 컨테이너와 같은 정책).
    CONTAINER.start();
  }

  private SharedMongoContainer() {}

  /**
   * 공유 컨테이너 주소를 Spring 설정에 등록한다.
   *
   * <p>{@code uri} 는 host·username 항목보다 우선하므로 이 한 줄이면 운영 설정을 통째로 덮는다.
   *
   * @param registry 테스트 Property Registry
   */
  public static void registerTo(DynamicPropertyRegistry registry) {
    registry.add("spring.data.mongodb.uri", CONTAINER::getReplicaSetUrl);
  }

  /**
   * 컬렉션을 비우고, 최초 1회 운영 인덱스를 재현한다.
   *
   * <p><b>drop 이 아니라 문서 삭제인 이유</b>: 컬렉션을 drop 하면 인덱스도 함께 사라진다. 그러면 멱등을 강제하는 {@code
   * session_batch_unique} 없이 다음 테스트가 돌아, 중복 저장이 통과하는 <b>가짜 초록</b>이 된다.
   *
   * <p>{@code counters} 도 비운다. MySQL 을 TRUNCATE 해 AUTO_INCREMENT 를 되돌리는 것과 같은 이유로, 발급되는 배치 ID가
   * 테스트마다 1부터 시작해야 실행 순서에 의존하지 않는다.
   *
   * @param mongoTemplate 초기화에 사용할 MongoDB Template
   */
  public static void reset(MongoTemplate mongoTemplate) {
    if (!indexesCreated) {
      // 앱은 인덱스를 만들지 않으므로(auto-index-creation: false) 테스트가 대신 만들어 주지 않으면
      //   운영에는 있고 테스트에는 없는 제약이 생긴다.
      mongoTemplate
          .indexOps("strokes")
          .createIndex(
              new Index().on("sessionId", ASC).on("batchSeq", ASC).unique().named(STROKE_UNIQUE));
      mongoTemplate.indexOps("strokes").createIndex(new Index().on("childId", ASC));
      indexesCreated = true;
    }
    mongoTemplate.remove(new Query(), "strokes");
    mongoTemplate.remove(new Query(), "counters");
  }
}
