package com.ssafy.b209;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * 아동 그림·대화 기반 정서 표현 서비스의 Spring Boot 진입점이다.
 *
 * <p>Application Context를 초기화하고 내장 웹 서버를 실행한다. 도메인 기능과 외부 시스템 연동은 각 기능의 후속 구현에서 구성한다.
 */
@SpringBootApplication
public class B209Application {

  /**
   * Spring 컨테이너가 애플리케이션 구성 클래스를 생성할 때 사용하는 생성자다.
   *
   * <p>애플리케이션 코드에서는 이 클래스를 직접 생성하지 않는다.
   */
  public B209Application() {}

  /**
   * Spring Boot 애플리케이션을 실행한다.
   *
   * @param args 애플리케이션 실행 시 전달되는 명령행 인자
   */
  public static void main(String[] args) {
    SpringApplication.run(B209Application.class, args);
  }
}
