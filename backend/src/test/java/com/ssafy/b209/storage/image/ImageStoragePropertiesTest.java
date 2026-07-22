package com.ssafy.b209.storage.image;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.global.config.TimeConfig;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

class ImageStoragePropertiesTest {

  private final ApplicationContextRunner contextRunner =
      new ApplicationContextRunner()
          .withUserConfiguration(ImageStorageConfig.class, TimeConfig.class);

  @Test
  void bindsDefaultValues() {
    contextRunner.run(
        context -> {
          assertThat(context).hasNotFailed();
          ImageStorageProperties properties = context.getBean(ImageStorageProperties.class);
          assertThat(properties.root())
              .isEqualTo(Path.of("storage", "images").toAbsolutePath().normalize());
          assertThat(properties.maxSize()).isEqualTo(10_485_760L);
          assertThat(context).hasSingleBean(ImageStorage.class);
        });
  }

  @Test
  void bindsOverriddenRootAndMaximumSize() {
    contextRunner
        .withPropertyValues(
            "app.storage.image.root=./custom/image-root", "app.storage.image.max-size=2048")
        .run(
            context -> {
              assertThat(context).hasNotFailed();
              ImageStorageProperties properties = context.getBean(ImageStorageProperties.class);
              assertThat(properties.root())
                  .isEqualTo(Path.of("custom", "image-root").toAbsolutePath().normalize());
              assertThat(properties.maxSize()).isEqualTo(2048L);
            });
  }

  @Test
  void rejectsZeroMaximumSize() {
    contextRunner
        .withPropertyValues("app.storage.image.max-size=0")
        .run(context -> assertThat(context).hasFailed());
  }

  @Test
  void rejectsNegativeMaximumSize() {
    contextRunner
        .withPropertyValues("app.storage.image.max-size=-1")
        .run(context -> assertThat(context).hasFailed());
  }

  @Test
  void rejectsBlankRoot() {
    org.assertj.core.api.Assertions.assertThatIllegalArgumentException()
        .isThrownBy(() -> new ImageStorageProperties(Path.of(""), 1024));
  }
}
