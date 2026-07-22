package com.ssafy.b209.auth.filter;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.auth.token.AuthenticatedUser;
import com.ssafy.b209.auth.token.JwtAccessTokenDecoder;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ErrorCode;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.List;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * {@code Authorization: Bearer} Access JWT를 검증하고 요청 동안 {@link AuthenticatedUser} Principal을 제공한다.
 *
 * <p>Token이 없는 요청의 접근 강제 정책은 309번 인증·인가 예외 전환에서 적용한다. Token이 전달된 경우에는 서명과 용도를 반드시 검증하며, 원본 Token이나
 * 내부 검증 오류를 응답에 노출하지 않는다.
 */
public class AccessTokenAuthenticationFilter extends OncePerRequestFilter {

  private static final String BEARER_PREFIX = "Bearer ";
  private static final String LEGACY_GUARDIAN_HEADER = "X-Guardian-User-Id";

  private final JwtAccessTokenDecoder decoder;
  private final ObjectMapper objectMapper;
  private final AuthFilterProperties properties;

  /**
   * Access Token Filter를 구성한다.
   *
   * @param decoder JWT 검증과 Principal 복원을 담당하는 Decoder
   * @param objectMapper 공통 오류 JSON 직렬화 도구
   * @param properties 임시 Header 전환 설정
   */
  public AccessTokenAuthenticationFilter(
      JwtAccessTokenDecoder decoder, ObjectMapper objectMapper, AuthFilterProperties properties) {
    this.decoder = decoder;
    this.objectMapper = objectMapper;
    this.properties = properties;
  }

  @Override
  protected void doFilterInternal(
      HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
      throws ServletException, IOException {
    String authorization = request.getHeader(HttpHeaders.AUTHORIZATION);
    if (authorization == null || authorization.isBlank() || isLegacyTestRequest(request)) {
      filterChain.doFilter(request, response);
      return;
    }
    if (!authorization.startsWith(BEARER_PREFIX)
        || authorization.length() == BEARER_PREFIX.length()) {
      writeError(response, AuthErrorCode.ACCESS_TOKEN_INVALID);
      return;
    }

    try {
      AuthenticatedUser principal = decoder.decode(authorization.substring(BEARER_PREFIX.length()));
      SecurityContext context = SecurityContextHolder.createEmptyContext();
      context.setAuthentication(
          UsernamePasswordAuthenticationToken.authenticated(principal, null, List.of()));
      SecurityContextHolder.setContext(context);
      filterChain.doFilter(request, response);
    } catch (JwtException exception) {
      writeError(response, AuthErrorCode.ACCESS_TOKEN_INVALID);
    } catch (BusinessException exception) {
      writeError(response, exception.getErrorCode());
    } finally {
      SecurityContextHolder.clearContext();
    }
  }

  private boolean isLegacyTestRequest(HttpServletRequest request) {
    return properties.legacyHeaderEnabled()
        && request.getHeader(LEGACY_GUARDIAN_HEADER) != null
        && !request.getHeader(LEGACY_GUARDIAN_HEADER).isBlank();
  }

  private void writeError(HttpServletResponse response, ErrorCode errorCode) throws IOException {
    response.setStatus(errorCode.getHttpStatus().value());
    response.setCharacterEncoding(StandardCharsets.UTF_8.name());
    response.setContentType(MediaType.APPLICATION_JSON_VALUE);
    objectMapper.writeValue(response.getOutputStream(), ApiErrorResponse.of(errorCode));
  }
}
