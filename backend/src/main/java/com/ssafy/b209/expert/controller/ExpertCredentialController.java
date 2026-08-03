package com.ssafy.b209.expert.controller;

import com.ssafy.b209.expert.dto.request.UploadExpertCredentialRequest;
import com.ssafy.b209.expert.dto.response.ExpertCredentialResponse;
import com.ssafy.b209.expert.exception.ExpertErrorCode;
import com.ssafy.b209.expert.service.ExpertCredentialManagementService;
import com.ssafy.b209.expert.service.ExpertCredentialUploadService;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonSuccessCode;
import com.ssafy.b209.storage.credential.CredentialFileStorageProperties;
import com.ssafy.b209.storage.credential.StoreCredentialFileCommand;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Positive;
import java.io.IOException;
import java.net.URI;
import java.util.List;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/** 전문가 본인의 자격 증빙 업로드 API를 제공한다. */
@Tag(name = "Expert Credentials", description = "전문가 자격 증빙 API")
@Validated
@RestController
@RequestMapping("/api/v1/experts/me/credentials")
public class ExpertCredentialController {
  private final ExpertCredentialUploadService uploadService;
  private final ExpertCredentialManagementService managementService;
  private final CredentialFileStorageProperties storageProperties;

  /**
   * 자격 업로드 서비스와 HTTP 사전 크기 제한을 주입한다.
   *
   * @param uploadService 자격 Metadata와 파일 저장 서비스
   * @param managementService 자격 목록 조회와 삭제 서비스
   * @param storageProperties 허용할 최대 파일 크기 설정
   */
  public ExpertCredentialController(
      ExpertCredentialUploadService uploadService,
      ExpertCredentialManagementService managementService,
      CredentialFileStorageProperties storageProperties) {
    this.uploadService = uploadService;
    this.managementService = managementService;
    this.storageProperties = storageProperties;
  }

  /**
   * 로그인 전문가가 등록한 자격 목록을 최신 등록 순으로 조회한다.
   *
   * @return 내부 Storage Key를 제외한 자격 목록
   */
  @Operation(summary = "내 자격 증빙 목록 조회")
  @GetMapping
  public ResponseEntity<ApiResponse<List<ExpertCredentialResponse>>> listMine() {
    return ResponseEntity.ok(ApiResponse.of(CommonSuccessCode.OK, managementService.listMine()));
  }

  /**
   * PDF/JPEG/PNG 파일과 JSON Metadata를 하나의 검토 대기 자격으로 등록한다.
   *
   * @param file 최대 10MiB 자격 증빙 파일
   * @param request 자격 분류·이름·발급 기관 Metadata
   * @return HTTP 201과 내부 Storage 정보가 제거된 자격 응답
   * @throws BusinessException 파일이 없거나 읽기·검증·저장에 실패한 경우
   */
  @Operation(summary = "전문가 자격 증빙 업로드")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "201",
        description = "자격 증빙 등록 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "400",
        description = "Metadata 또는 파일 형식 오류",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "413",
        description = "파일 크기 제한 초과",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
  public ResponseEntity<ApiResponse<ExpertCredentialResponse>> upload(
      @RequestPart(value = "file", required = false) MultipartFile file,
      @Valid @RequestPart(value = "metadata", required = false)
          UploadExpertCredentialRequest request) {
    if (file == null || file.isEmpty() || request == null) {
      throw new BusinessException(ExpertErrorCode.CREDENTIAL_FILE_INVALID);
    }
    if (file.getSize() > storageProperties.maxSize()) {
      throw new BusinessException(ExpertErrorCode.CREDENTIAL_FILE_TOO_LARGE);
    }
    try {
      ExpertCredentialResponse response =
          uploadService.upload(
              new StoreCredentialFileCommand(
                  file.getBytes(), file.getContentType(), file.getOriginalFilename()),
              request);
      return ResponseEntity.created(
              URI.create("/api/v1/experts/me/credentials/" + response.credentialId()))
          .body(ApiResponse.of(CommonSuccessCode.CREATED, response));
    } catch (IOException exception) {
      throw new BusinessException(ExpertErrorCode.CREDENTIAL_STORAGE_FAILED, exception);
    }
  }

  /**
   * 아직 관리자 검토가 시작되지 않은 본인 자격을 삭제한다.
   *
   * @param credentialId 삭제할 자격 식별자
   * @return 본문 없는 HTTP 204 응답
   */
  @Operation(summary = "검토 전 내 자격 증빙 삭제")
  @ApiResponses({
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "204",
        description = "자격 증빙 삭제 성공"),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "404",
        description = "자격이 없거나 본인 소유가 아님",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))),
    @io.swagger.v3.oas.annotations.responses.ApiResponse(
        responseCode = "409",
        description = "검토 이력이 있어 삭제할 수 없음",
        content = @Content(schema = @Schema(implementation = ApiErrorResponse.class)))
  })
  @DeleteMapping("/{credentialId}")
  public ResponseEntity<Void> deleteMine(@PathVariable @Positive Long credentialId) {
    managementService.deleteMine(credentialId);
    return ResponseEntity.noContent().build();
  }
}
