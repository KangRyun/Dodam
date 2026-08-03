package com.ssafy.b209.expert.dto.response;

import com.ssafy.b209.expert.domain.ExpertVerificationStatus;
import java.time.Instant;
import java.time.LocalDate;

/**
 * 전문가가 등록한 자격과 증빙 파일의 공개 가능한 Metadata다.
 *
 * <p>내부 Storage Key와 Checksum은 응답에 포함하지 않는다.
 *
 * @param credentialId 전문가 자격 식별자
 * @param credentialType 자격 분류 코드
 * @param credentialName 자격명
 * @param issuer 발급 기관
 * @param issuedAt 취득일
 * @param credentialNumberMasked 마스킹 자격 번호
 * @param verificationStatus 검토 상태
 * @param fileName 원본 파일명
 * @param mimeType 검증된 파일 MIME Type
 * @param fileSizeBytes 실제 저장 크기
 * @param createdAt 등록 시각
 */
public record ExpertCredentialResponse(
    Long credentialId,
    String credentialType,
    String credentialName,
    String issuer,
    LocalDate issuedAt,
    String credentialNumberMasked,
    ExpertVerificationStatus verificationStatus,
    String fileName,
    String mimeType,
    long fileSizeBytes,
    Instant createdAt) {}
