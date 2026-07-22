package com.ssafy.b209.auth.config;

import com.ssafy.b209.auth.service.OAuthProviderProperties;
import com.ssafy.b209.auth.token.JwtProperties;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;

/** OAuth Provider와 서비스 JWT 발급에 필요한 외부 설정을 활성화한다. */
@Configuration
@EnableConfigurationProperties({OAuthProviderProperties.class, JwtProperties.class})
public class AuthConfig {

  /** Spring이 인증 설정 Bean을 등록할 때 사용하는 생성자이다. */
  public AuthConfig() {}
}
