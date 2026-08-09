package com.ssafy.b209.community.service;

import com.ssafy.b209.community.domain.CommunityAttachmentFile;
import com.ssafy.b209.community.dto.CommunityAttachmentInput;
import com.ssafy.b209.community.dto.CommunityAttachmentResponse;
import com.ssafy.b209.community.exception.CommunityAttachmentErrorCode;
import com.ssafy.b209.community.repository.CommunityAttachmentDeletionRepository;
import com.ssafy.b209.community.repository.CommunityAttachmentFileRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 사전 업로드 이미지의 소유권·만료 여부를 검증하고 게시글에 순서대로 연결한다. */
@Service
public class CommunityAttachmentService {

  private static final String FILE_URL_PREFIX = "/api/v1/community-files/";
  private static final String FILE_URL_SUFFIX = "/file";

  private final CommunityAttachmentFileRepository repository;
  private final CommunityAttachmentDeletionRepository deletionRepository;
  private final Clock clock;

  /**
   * 첨부 연결에 필요한 Metadata·삭제 작업 저장소와 시간 기준을 구성한다.
   *
   * @param repository 첨부 Metadata 저장소
   * @param deletionRepository Storage 삭제 작업 저장소
   * @param clock 만료·연결 시각 기준
   */
  public CommunityAttachmentService(
      CommunityAttachmentFileRepository repository,
      CommunityAttachmentDeletionRepository deletionRepository,
      Clock clock) {
    this.repository = repository;
    this.deletionRepository = deletionRepository;
    this.clock = clock;
  }

  /**
   * 요청 순서를 유지해 임시 첨부 파일을 게시글에 연결한다.
   *
   * @param userId 게시글 작성 사용자 ID
   * @param postId 생성된 게시글 ID
   * @param inputs 연결할 사전 업로드 파일 목록
   * @return 게시글 응답에 노출할 첨부 목록
   * @throws BusinessException 중복 참조, 소유하지 않은 파일, 만료 또는 재사용 파일인 경우
   */
  public List<CommunityAttachmentResponse> attach(
      Long userId, Long postId, List<CommunityAttachmentInput> inputs) {
    if (inputs == null || inputs.isEmpty()) {
      return List.of();
    }
    List<String> fileIds = inputs.stream().map(CommunityAttachmentInput::fileId).toList();
    Set<String> uniqueIds = new HashSet<>(fileIds);
    if (uniqueIds.size() != fileIds.size()) {
      throw new BusinessException(CommunityAttachmentErrorCode.DUPLICATED);
    }
    Map<String, CommunityAttachmentFile> files = new HashMap<>();
    repository
        .findOwnedFilesForUpdate(uniqueIds, userId)
        .forEach(file -> files.put(file.getFileId(), file));
    if (files.size() != uniqueIds.size()) {
      throw new BusinessException(CommunityAttachmentErrorCode.NOT_FOUND);
    }

    LocalDateTime now = LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
    for (int index = 0; index < inputs.size(); index++) {
      CommunityAttachmentFile file = files.get(inputs.get(index).fileId());
      try {
        file.attachTo(postId, index, now);
      } catch (IllegalStateException exception) {
        throw new BusinessException(CommunityAttachmentErrorCode.NOT_ATTACHABLE);
      }
    }
    return inputs.stream().map(input -> toResponse(files.get(input.fileId()))).toList();
  }

  /**
   * 게시글 첨부 목록을 요청 목록으로 교체한다.
   *
   * <p>같은 게시글에 이미 연결된 파일은 순서만 바꾸고, 새 임시 파일은 소유권·만료를 검증해 연결한다. 목록에서 빠진 파일은 Transaction과 함께 삭제 작업을
   * 예약한다.
   *
   * @param userId 게시글 작성 사용자 ID
   * @param postId 수정할 게시글 ID
   * @param inputs 교체할 첨부 목록
   * @return 새 노출 순서의 첨부 목록
   */
  @Transactional
  public List<CommunityAttachmentResponse> replace(
      Long userId, Long postId, List<CommunityAttachmentInput> inputs) {
    List<CommunityAttachmentInput> requested = inputs == null ? List.of() : List.copyOf(inputs);
    Set<String> requestedIds = new HashSet<>();
    for (CommunityAttachmentInput input : requested) {
      if (!requestedIds.add(input.fileId())) {
        throw new BusinessException(CommunityAttachmentErrorCode.DUPLICATED);
      }
    }

    Map<String, CommunityAttachmentFile> selected = new HashMap<>();
    List<CommunityAttachmentFile> existing = repository.findAllByPostIdForUpdate(postId);
    existing.forEach(file -> selected.put(file.getFileId(), file));
    Set<String> newIds = new HashSet<>(requestedIds);
    newIds.removeAll(selected.keySet());
    if (!newIds.isEmpty()) {
      repository
          .findOwnedFilesForUpdate(newIds, userId)
          .forEach(file -> selected.put(file.getFileId(), file));
    }
    if (!selected.keySet().containsAll(requestedIds)) {
      throw new BusinessException(CommunityAttachmentErrorCode.NOT_FOUND);
    }

    LocalDateTime now = LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
    for (int index = 0; index < requested.size(); index++) {
      CommunityAttachmentFile file = selected.get(requested.get(index).fileId());
      try {
        if (file.getStatus()
            == com.ssafy.b209.community.domain.CommunityAttachmentStatus.ATTACHED) {
          file.reorder(postId, index);
        } else {
          file.attachTo(postId, index, now);
        }
      } catch (IllegalStateException exception) {
        throw new BusinessException(CommunityAttachmentErrorCode.NOT_ATTACHABLE);
      }
    }
    existing.stream()
        .filter(file -> !requestedIds.contains(file.getFileId()))
        .forEach(
            file -> {
              deletionRepository.schedule(file.getStorageKey(), file.getId());
              repository.delete(file);
            });
    return requested.stream().map(input -> toResponse(selected.get(input.fileId()))).toList();
  }

  /** 게시글 삭제 시 연결된 파일의 Storage 삭제를 예약하고 Metadata를 제거한다. */
  @Transactional
  public void deleteByPostId(Long postId) {
    repository
        .findAllByPostIdForUpdate(postId)
        .forEach(
            file -> {
              deletionRepository.schedule(file.getStorageKey(), file.getId());
              repository.delete(file);
            });
  }

  /** 게시글에 연결된 첨부 목록을 저장된 노출 순서대로 반환한다. */
  public List<CommunityAttachmentResponse> findByPostId(Long postId) {
    return repository.findAllByPostIdOrderByDisplayOrderAsc(postId).stream()
        .map(this::toResponse)
        .toList();
  }

  private CommunityAttachmentResponse toResponse(CommunityAttachmentFile file) {
    return new CommunityAttachmentResponse(
        file.getFileId(),
        com.ssafy.b209.community.domain.CommunityAttachmentType.IMAGE,
        FILE_URL_PREFIX + file.getFileId() + FILE_URL_SUFFIX,
        file.getWidthPx(),
        file.getHeightPx());
  }
}
