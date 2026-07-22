package com.ssafy.b209.auth.repository;

import com.ssafy.b209.auth.domain.User;
import org.springframework.data.jpa.repository.JpaRepository;

/** OAuth 계정과 서비스 프로필이 참조하는 사용자를 저장한다. */
public interface UserRepository extends JpaRepository<User, Long> {}
