package com.ssafy.b209.community.controller;

import com.ssafy.b209.community.dto.ComplaintCreateRequest;
import com.ssafy.b209.community.dto.ComplaintResponse;
import com.ssafy.b209.community.service.CommunityComplaintService;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonSuccessCode;
import jakarta.validation.Valid;
import java.net.URI;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** 로그인 사용자가 공개 콘텐츠를 운영자에게 신고하는 통합 API다. */
@RestController
@RequestMapping("/api/v1/complaints")
public class CommunityComplaintController {

  private final CommunityComplaintService complaintService;

  /**
   * @param complaintService 대상 검증과 중복 방지를 수행하는 신고 서비스
   */
  public CommunityComplaintController(CommunityComplaintService complaintService) {
    this.complaintService = complaintService;
  }

  /**
   * 게시글·댓글·접근 가능한 리포트 신고를 접수한다.
   *
   * @param request 대상과 표준 사유가 포함된 요청
   * @return HTTP 201과 생성된 신고 식별 정보
   */
  @PostMapping
  public ResponseEntity<ApiResponse<ComplaintResponse>> createComplaint(
      @Valid @RequestBody ComplaintCreateRequest request) {
    ComplaintResponse response = complaintService.createComplaint(request);
    return ResponseEntity.created(URI.create("/api/v1/complaints/" + response.complaintId()))
        .body(ApiResponse.of(CommonSuccessCode.CREATED, response));
  }
}
