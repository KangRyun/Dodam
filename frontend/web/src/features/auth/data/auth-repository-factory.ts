import { ApiAuthRepository } from "@/features/auth/data/api/api-auth-repository";
import type { AuthRepository } from "@/features/auth/domain/auth-repository";

/** 인증 저장소를 만든다. 앱과 동일한 백엔드를 호출하는 실제 구현을 쓴다. */
export function createAuthRepository(): AuthRepository {
  return new ApiAuthRepository();
}

/** 앱 전역에서 재사용하는 단일 인증 저장소 인스턴스. */
export const authRepository = createAuthRepository();
