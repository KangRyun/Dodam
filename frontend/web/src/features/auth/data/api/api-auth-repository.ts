import {
  type ConsentTermDto,
  type OAuthLoginResultDto,
  type UserResponseDto,
  toSession,
  toTerm,
  toUser,
} from "@/features/auth/data/auth-dto";
import type {
  AuthProviderId,
  AuthSession,
  AuthUser,
  ConsentTerm,
  OnboardingInput,
  ProviderToken,
} from "@/features/auth/domain/auth-models";
import type { AuthRepository } from "@/features/auth/domain/auth-repository";
import { apiRequest } from "@/lib/api/api-client";

/**
 * 앱과 동일한 백엔드 계약을 호출하는 실제 인증 저장소.
 *
 * 각 사 JS SDK로 브라우저에서 받은 provider 토큰을 그대로 백엔드에 보낸다.
 */
export class ApiAuthRepository implements AuthRepository {
  async signIn(input: {
    provider: AuthProviderId;
    token: ProviderToken;
    deviceId: string;
  }): Promise<AuthSession> {
    const result = await apiRequest<OAuthLoginResultDto>(
      `auth/oauth/${input.provider}`,
      {
        method: "POST",
        body: JSON.stringify({
          accessToken: input.token.accessToken ?? null,
          idToken: input.token.idToken ?? null,
          deviceId: input.deviceId,
        }),
      },
    );
    return toSession(result);
  }

  async reissue(input: {
    refreshToken: string;
    deviceId: string;
  }): Promise<AuthSession> {
    const result = await apiRequest<OAuthLoginResultDto>("auth/reissue", {
      method: "POST",
      body: JSON.stringify({
        refreshToken: input.refreshToken,
        deviceId: input.deviceId,
      }),
    });
    return toSession(result);
  }

  async logout(input: {
    refreshToken: string;
    deviceId: string;
  }): Promise<void> {
    await apiRequest<void>("auth/logout", {
      method: "POST",
      body: JSON.stringify({
        refreshToken: input.refreshToken,
        deviceId: input.deviceId,
      }),
    });
  }

  async deleteAccount(input: {
    refreshToken: string;
    deviceId: string;
  }): Promise<void> {
    await apiRequest<void>("users/me", {
      method: "DELETE",
      body: JSON.stringify({
        refreshToken: input.refreshToken,
        deviceId: input.deviceId,
      }),
    });
  }

  async getTerms(): Promise<ConsentTerm[]> {
    const terms = await apiRequest<ConsentTermDto[]>(
      "consents/terms?targetScope=USER",
    );
    return terms.map(toTerm);
  }

  async completeOnboarding(input: OnboardingInput): Promise<AuthUser> {
    const result = await apiRequest<UserResponseDto>("users/me/onboarding", {
      method: "PUT",
      body: JSON.stringify({
        role: input.role,
        nickname: input.nickname,
        email: input.email,
        profileImageFileId: null,
        consents: input.consents,
      }),
    });
    return toUser(result);
  }

  async getMe(): Promise<AuthUser> {
    const result = await apiRequest<UserResponseDto>("users/me");
    return toUser(result);
  }
}
