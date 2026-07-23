package com.ssafy.b209.infrastructure.mockdata;

import javax.sql.DataSource;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;

/**
 * 로컬 개발 환경의 MVP 테스트 데이터를 초기화한다.
 *
 * <p>{@code local} Profile과 {@code app.mock-data.enabled=true}가 함께 적용될 때만 구성되며, Flyway가 생성한 Schema에
 * 별도 Seed SQL을 실행한다. 운영 환경에서는 이 설정을 활성화하지 않아야 한다.
 */
@Configuration(proxyBeanMethods = false)
@Profile("local")
@ConditionalOnProperty(prefix = "app.mock-data", name = "enabled", havingValue = "true")
public class MvpMockDataConfiguration {

  /**
   * 애플리케이션 시작 시 MVP 개발 데이터를 주입하는 Runner를 제공한다.
   *
   * @param dataSource 로컬 MySQL 연결을 제공하는 DataSource
   * @return Seed SQL을 실행하는 ApplicationRunner
   */
  @Bean
  ApplicationRunner mvpMockDataInitializer(DataSource dataSource) {
    return arguments -> {
      ResourceDatabasePopulator populator =
          new ResourceDatabasePopulator(new ClassPathResource("db/mock/mvp-mock-data.sql"));
      populator.execute(dataSource);
    };
  }
}
