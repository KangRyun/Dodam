package com.ssafy.b209.storage.s3;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.global.config.TimeConfig;
import com.ssafy.b209.storage.audio.AudioStorage;
import com.ssafy.b209.storage.audio.AudioStorageConfig;
import com.ssafy.b209.storage.audio.LocalAudioStorage;
import com.ssafy.b209.storage.credential.CredentialFileStorage;
import com.ssafy.b209.storage.image.ImageStorage;
import com.ssafy.b209.storage.image.ImageStorageConfig;
import com.ssafy.b209.storage.image.LocalImageStorage;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import software.amazon.awssdk.services.s3.S3Client;

class S3StorageConfigTest {

  private final ApplicationContextRunner contextRunner =
      new ApplicationContextRunner()
          .withUserConfiguration(
              ImageStorageConfig.class,
              AudioStorageConfig.class,
              S3StorageConfig.class,
              TimeConfig.class);

  @Test
  void localModeRegistersOnlyLocalStorageBeans() {
    contextRunner
        .withPropertyValues("app.storage.mode=local")
        .run(
            context -> {
              assertThat(context).hasNotFailed();
              assertThat(context.getBean(ImageStorage.class)).isInstanceOf(LocalImageStorage.class);
              assertThat(context.getBean(AudioStorage.class)).isInstanceOf(LocalAudioStorage.class);
              assertThat(context).doesNotHaveBean(S3Client.class);
            });
  }

  @Test
  void s3ModeRegistersClientWithoutLocalStorageBeans() {
    contextRunner
        .withPropertyValues(
            "app.storage.mode=s3",
            "app.storage.s3.endpoint=http://localhost:9000",
            "app.storage.s3.region=ap-northeast-2",
            "app.storage.s3.bucket=dodam",
            "app.storage.s3.access-key=integration-user",
            "app.storage.s3.secret-key=integration-password")
        .run(
            context -> {
              assertThat(context).hasNotFailed();
              assertThat(context).hasSingleBean(S3Client.class);
              assertThat(context.getBean(ImageStorage.class)).isInstanceOf(S3ImageStorage.class);
              assertThat(context.getBean(AudioStorage.class)).isInstanceOf(S3AudioStorage.class);
              assertThat(context.getBean(CredentialFileStorage.class))
                  .isInstanceOf(S3CredentialFileStorage.class);
            });
  }

  @Test
  void s3ModeRejectsBlankCredentials() {
    contextRunner
        .withPropertyValues(
            "app.storage.mode=s3",
            "app.storage.s3.endpoint=http://localhost:9000",
            "app.storage.s3.bucket=dodam",
            "app.storage.s3.access-key=",
            "app.storage.s3.secret-key=")
        .run(context -> assertThat(context).hasFailed());
  }
}
