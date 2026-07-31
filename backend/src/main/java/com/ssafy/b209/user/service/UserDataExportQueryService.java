package com.ssafy.b209.user.service;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.user.dto.response.DataExportJobStatusResponse;
import com.ssafy.b209.user.exception.UserErrorCode;
import com.ssafy.b209.user.repository.DataExportJobRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 인증 사용자가 소유한 데이터 내보내기 작업 상태를 조회한다. */
@Service
public class UserDataExportQueryService {

  private final DataExportJobRepository dataExportJobRepository;

  /**
   * 데이터 내보내기 상태 조회 서비스를 구성한다.
   *
   * @param dataExportJobRepository 내보내기 작업 조회 저장소
   */
  public UserDataExportQueryService(DataExportJobRepository dataExportJobRepository) {
    this.dataExportJobRepository = dataExportJobRepository;
  }

  /**
   * 인증 사용자가 소유한 작업의 현재 공개 상태를 조회한다.
   *
   * <p>작업 미존재와 타인 소유는 같은 404로 처리하여 작업 존재 여부를 노출하지 않는다. 저장 Key·다운로드 URL·파일 크기·체크섬은 반환하지 않는다.
   *
   * @param userId 인증된 요청 사용자 식별자
   * @param exportId 조회할 데이터 내보내기 작업 식별자
   * @return 공개 가능한 작업 상태
   * @throws BusinessException 작업이 없거나 요청 사용자가 소유하지 않은 경우
   */
  @Transactional(readOnly = true)
  public DataExportJobStatusResponse get(Long userId, Long exportId) {
    return dataExportJobRepository
        .findByIdAndUserId(exportId, userId)
        .map(DataExportJobStatusResponse::from)
        .orElseThrow(() -> new BusinessException(UserErrorCode.DATA_EXPORT_JOB_NOT_FOUND));
  }
}
