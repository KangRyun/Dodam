import type { CreateCommunityComplaintInput } from "@/features/community/domain/community-models";
import { apiRequest } from "@/lib/api/api-client";

/** COMM-11 실제 백엔드 공통 신고 API만 호출한다. */
export async function createCommunityComplaint(
  input: CreateCommunityComplaintInput,
): Promise<void> {
  await apiRequest<unknown>("/complaints", {
    method: "POST",
    body: JSON.stringify(input),
  });
}
