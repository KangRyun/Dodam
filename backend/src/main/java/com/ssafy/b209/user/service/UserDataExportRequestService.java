package com.ssafy.b209.user.service;

import com.ssafy.b209.user.domain.DataExportJob;
import com.ssafy.b209.user.dto.response.DataExportJobResponse;
import com.ssafy.b209.user.repository.DataExportJobRepository;
import java.time.Clock;
import java.time.LocalDateTime;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 인증 사용자의 데이터 내보내기 작업 접수를 저장한다. */
@Service
public class UserDataExportRequestService {

  private final DataExportJobRepository dataExportJobRepository;
  private final Clock clock;

  /**
   * 데이터 내보내기 요청 서비스를 구성한다.
   *
   * @param dataExportJobRepository 내보내기 작업 저장소
   * @param clock 접수 시각을 제공하는 시계
   */
  public UserDataExportRequestService(
      DataExportJobRepository dataExportJobRepository, Clock clock) {
    this.dataExportJobRepository = dataExportJobRepository;
    this.clock = clock;
  }

  /**
   * 인증 사용자의 새 데이터 내보내기 작업을 대기 상태로 접수한다.
   *
   * <p>이 Use Case는 작업 행만 생성한다. ZIP 조립, 파일 저장, 상태 조회는 후속 이슈의 책임이다.
   *
   * @param userId 인증된 요청 사용자 식별자
   * @return 생성된 작업의 공개 상태
   */
  @Transactional
  public DataExportJobResponse request(Long userId) {
    DataExportJob job =
        dataExportJobRepository.save(DataExportJob.requested(userId, LocalDateTime.now(clock)));
    return DataExportJobResponse.from(job);
  }
}
