package com.ssafy.b209.user.service;

import com.ssafy.b209.user.dto.request.DataRetentionPolicyUpdateRequest;
import com.ssafy.b209.user.dto.response.DataRetentionPolicyResponse;
import com.ssafy.b209.user.repository.UserDataRetentionSettingsRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 로그인 사용자 본인의 데이터 보관 정책을 변경한다.
 *
 * <p>요청은 두 값을 모두 담은 전체 교체다. 행 존재 여부를 애플리케이션에서 조회해 분기하지 않고 저장소의 원자적 upsert에 위임한다. 저장 직후 기존 조회기를 사용해
 * 응답을 만들므로 GET과 PATCH의 응답 매핑 및 {@code policyStatus=PROVISIONAL} 규약이 같다.
 */
@Service
@Transactional
public class UserDataRetentionPolicyUpdateService {

  private final UserDataRetentionSettingsRepository dataRetentionSettingsRepository;
  private final UserDataRetentionPolicyReader dataRetentionPolicyReader;

  /**
   * 데이터 보관 정책 변경기를 구성한다.
   *
   * @param dataRetentionSettingsRepository 사용자 데이터 보관 설정 저장소
   * @param dataRetentionPolicyReader 저장 후 최신 정책을 읽어 응답으로 만드는 조회기
   */
  public UserDataRetentionPolicyUpdateService(
      UserDataRetentionSettingsRepository dataRetentionSettingsRepository,
      UserDataRetentionPolicyReader dataRetentionPolicyReader) {
    this.dataRetentionSettingsRepository = dataRetentionSettingsRepository;
    this.dataRetentionPolicyReader = dataRetentionPolicyReader;
  }

  /**
   * 사용자의 데이터 보관 정책을 요청 값으로 저장하고 최신 상태를 반환한다.
   *
   * @param userId 대상 사용자 식별자
   * @param request 저장할 데이터 보관 정책 두 값
   * @return 저장 후 최신 데이터 보관 정책
   */
  public DataRetentionPolicyResponse update(Long userId, DataRetentionPolicyUpdateRequest request) {
    dataRetentionSettingsRepository.upsert(
        userId, request.retentionDays(), request.noticeDaysBefore());
    return dataRetentionPolicyReader.read(userId);
  }
}
