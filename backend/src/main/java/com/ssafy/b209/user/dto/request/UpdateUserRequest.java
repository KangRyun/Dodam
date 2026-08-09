package com.ssafy.b209.user.dto.request;

import jakarta.validation.constraints.Size;

/**
 * 로그인 사용자가 본인 프로필의 일부 필드를 수정하는 요청이다.
 *
 * <p>변경할 필드만 전달하며 전달하지 않은 필드는 유지한다. {@code profileImageFileId}는 계약 호환을 위해 받지만 현재 사전 업로드 이미지를 연결하는
 * 기반이 없어 반영하지 않는다.
 *
 * @param nickname 변경할 닉네임, 유지하려면 {@code null}
 * @param profileImageFileId 변경할 프로필 이미지 식별자, 유지하려면 {@code null}
 */
public record UpdateUserRequest(
    @Size(max = 50) String nickname, @Size(max = 255) String profileImageFileId) {}
