package com.ssafy.b209.expert.repository;

import com.ssafy.b209.expert.domain.ExpertCredential;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 전문가 자격과 연결 증빙 파일을 함께 영속화하는 저장소다. */
public interface ExpertCredentialRepository extends JpaRepository<ExpertCredential, Long> {

  /**
   * 로그인 전문가가 보유한 자격과 증빙 파일을 최신 등록 순으로 조회한다.
   *
   * @param userId 로그인 사용자 식별자
   * @return 해당 전문가 소유 자격 목록
   */
  @EntityGraph(attributePaths = "files")
  @Query(
      "select credential from ExpertCredential credential "
          + "where credential.expertProfile.userId = :userId "
          + "order by credential.createdAt desc, credential.id desc")
  List<ExpertCredential> findAllOwnedByUserId(@Param("userId") Long userId);

  /**
   * 로그인 전문가가 소유한 단일 자격과 증빙 파일을 조회한다.
   *
   * @param credentialId 자격 식별자
   * @param userId 로그인 사용자 식별자
   * @return 소유권이 일치하는 자격, 없으면 빈 값
   */
  @EntityGraph(attributePaths = "files")
  @Query(
      "select credential from ExpertCredential credential "
          + "where credential.id = :credentialId "
          + "and credential.expertProfile.userId = :userId")
  Optional<ExpertCredential> findOwnedById(
      @Param("credentialId") Long credentialId, @Param("userId") Long userId);
}
