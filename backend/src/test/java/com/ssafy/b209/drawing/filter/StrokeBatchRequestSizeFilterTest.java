package com.ssafy.b209.drawing.filter;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletRequest;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicBoolean;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

class StrokeBatchRequestSizeFilterTest {

  private final StrokeBatchRequestSizeFilter filter =
      new StrokeBatchRequestSizeFilter(new ObjectMapper());

  @Test
  void acceptsARequestAtExactlyOneMebibyte() throws Exception {
    byte[] body = new byte[StrokeBatchRequestSizeFilter.MAX_REQUEST_BYTES];
    MockHttpServletRequest request = request(body);
    MockHttpServletResponse response = new MockHttpServletResponse();
    AtomicBoolean invoked = new AtomicBoolean();

    filter.doFilter(
        request,
        response,
        (wrappedRequest, wrappedResponse) -> {
          invoked.set(true);
          byte[] forwarded = ((HttpServletRequest) wrappedRequest).getInputStream().readAllBytes();
          assertThat(forwarded).hasSize(StrokeBatchRequestSizeFilter.MAX_REQUEST_BYTES);
        });

    assertThat(invoked).isTrue();
  }

  @Test
  void rejectsARequestOneByteOverTheLimitWithActionableError() throws Exception {
    byte[] body = new byte[StrokeBatchRequestSizeFilter.MAX_REQUEST_BYTES + 1];
    MockHttpServletRequest request = request(body);
    MockHttpServletResponse response = new MockHttpServletResponse();
    AtomicBoolean invoked = new AtomicBoolean();

    filter.doFilter(request, response, (ignoredRequest, ignoredResponse) -> invoked.set(true));

    assertThat(invoked).isFalse();
    assertThat(response.getStatus()).isEqualTo(413);
    assertThat(response.getContentAsString(StandardCharsets.UTF_8))
        .contains("\"code\":\"DRAWING_413_001\"")
        .contains("1 MiB");
  }

  @Test
  void rejectsAnOversizedBodyWhenContentLengthIsUnknown() throws Exception {
    byte[] body = new byte[StrokeBatchRequestSizeFilter.MAX_REQUEST_BYTES + 1];
    MockHttpServletRequest request =
        new MockHttpServletRequest("POST", "/api/v1/drawing-sessions/100/stroke-batches") {
          @Override
          public long getContentLengthLong() {
            return -1;
          }
        };
    request.setContentType("application/json");
    request.setContent(body);
    MockHttpServletResponse response = new MockHttpServletResponse();
    AtomicBoolean invoked = new AtomicBoolean();

    filter.doFilter(request, response, (ignoredRequest, ignoredResponse) -> invoked.set(true));

    assertThat(invoked).isFalse();
    assertThat(response.getStatus()).isEqualTo(413);
  }

  private MockHttpServletRequest request(byte[] body) {
    MockHttpServletRequest request =
        new MockHttpServletRequest("POST", "/api/v1/drawing-sessions/100/stroke-batches");
    request.setContentType("application/json");
    request.setContent(body);
    return request;
  }
}
