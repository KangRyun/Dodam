package com.ssafy.b209.drawing.filter;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.drawing.exception.DrawingErrorCode;
import com.ssafy.b209.global.response.ApiErrorResponse;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ReadListener;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletInputStream;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletRequestWrapper;
import jakarta.servlet.http.HttpServletResponse;
import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.regex.Pattern;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Stroke 배치 JSON을 역직렬화하기 전에 압축 전 요청 Body를 1 MiB로 제한한다.
 *
 * <p>{@code Content-Length}가 없는 Chunked 요청도 최대 크기보다 한 Byte만 더 읽어 판정한다. 허용된 Body는 메모리에 한 번만 보관해
 * Controller의 JSON 역직렬화에 다시 제공하며, 제한 초과 요청은 공통 413 응답으로 즉시 종료한다.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 20)
public class StrokeBatchRequestSizeFilter extends OncePerRequestFilter {

  static final int MAX_REQUEST_BYTES = 1024 * 1024;
  private static final Pattern STROKE_BATCH_PATH =
      Pattern.compile("^/api/v1/drawing-sessions/[^/]+/stroke-batches$");

  private final ObjectMapper objectMapper;

  /**
   * 공통 오류 응답을 직렬화할 Jackson Mapper를 주입한다.
   *
   * @param objectMapper 애플리케이션 공통 JSON Mapper
   */
  public StrokeBatchRequestSizeFilter(ObjectMapper objectMapper) {
    this.objectMapper = objectMapper;
  }

  /** {@inheritDoc} */
  @Override
  protected boolean shouldNotFilter(HttpServletRequest request) {
    return !"POST".equalsIgnoreCase(request.getMethod())
        || !STROKE_BATCH_PATH.matcher(request.getRequestURI()).matches();
  }

  /** {@inheritDoc} */
  @Override
  protected void doFilterInternal(
      HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
      throws ServletException, IOException {
    if (request.getContentLengthLong() > MAX_REQUEST_BYTES) {
      reject(response);
      return;
    }

    byte[] body = request.getInputStream().readNBytes(MAX_REQUEST_BYTES + 1);
    if (body.length > MAX_REQUEST_BYTES) {
      reject(response);
      return;
    }
    filterChain.doFilter(new CachedBodyRequest(request, body), response);
  }

  private void reject(HttpServletResponse response) throws IOException {
    response.setStatus(DrawingErrorCode.STROKE_BATCH_PAYLOAD_TOO_LARGE.getHttpStatus().value());
    response.setContentType(MediaType.APPLICATION_JSON_VALUE);
    response.setCharacterEncoding(StandardCharsets.UTF_8.name());
    objectMapper.writeValue(
        response.getOutputStream(),
        ApiErrorResponse.of(DrawingErrorCode.STROKE_BATCH_PAYLOAD_TOO_LARGE));
  }

  private static final class CachedBodyRequest extends HttpServletRequestWrapper {

    private final byte[] body;

    private CachedBodyRequest(HttpServletRequest request, byte[] body) {
      super(request);
      this.body = body;
    }

    @Override
    public ServletInputStream getInputStream() {
      ByteArrayInputStream input = new ByteArrayInputStream(body);
      return new ServletInputStream() {
        @Override
        public boolean isFinished() {
          return input.available() == 0;
        }

        @Override
        public boolean isReady() {
          return true;
        }

        @Override
        public void setReadListener(ReadListener readListener) {
          throw new UnsupportedOperationException("asynchronous read is not supported");
        }

        @Override
        public int read() {
          return input.read();
        }

        @Override
        public int read(byte[] bytes, int offset, int length) {
          return input.read(bytes, offset, length);
        }
      };
    }

    @Override
    public BufferedReader getReader() {
      return new BufferedReader(new InputStreamReader(getInputStream(), StandardCharsets.UTF_8));
    }
  }
}
