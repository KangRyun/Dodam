package com.ssafy.b209.infrastructure.mockdata;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import javax.sql.DataSource;
import org.junit.jupiter.api.Test;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

class MvpMockDataConfigurationTest {

  private final ApplicationContextRunner contextRunner =
      new ApplicationContextRunner()
          .withUserConfiguration(MvpMockDataConfiguration.class, DataSourceConfiguration.class);

  @Test
  void enablesInitializerOnlyForLocalProfileWithExplicitFlag() {
    contextRunner
        .withPropertyValues("spring.profiles.active=local", "app.mock-data.enabled=true")
        .run(context -> assertThat(context).hasSingleBean(ApplicationRunner.class));
  }

  @Test
  void disablesInitializerWhenFlagIsFalse() {
    contextRunner
        .withPropertyValues("spring.profiles.active=local", "app.mock-data.enabled=false")
        .run(context -> assertThat(context).doesNotHaveBean(ApplicationRunner.class));
  }

  @Test
  void disablesInitializerOutsideLocalProfile() {
    contextRunner
        .withPropertyValues("spring.profiles.active=test", "app.mock-data.enabled=true")
        .run(context -> assertThat(context).doesNotHaveBean(ApplicationRunner.class));
  }

  @Configuration(proxyBeanMethods = false)
  static class DataSourceConfiguration {

    @Bean
    DataSource dataSource() {
      return mock(DataSource.class);
    }
  }
}
