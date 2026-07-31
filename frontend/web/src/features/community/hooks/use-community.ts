"use client";

import {
  useMutation,
  useQuery,
  useQueryClient,
  type UseMutationResult,
  type UseQueryResult,
} from "@tanstack/react-query";

import { communityRepository } from "@/features/community/data/community-repository-factory";
import type {
  CommunityFeed,
  CommunityPost,
  CommunityPostFilter,
  CreateCommunityPostInput,
  UpdateCommunityPostInput,
} from "@/features/community/domain/community-models";

/** React Query 캐시 키. 게시글 변경 시 관련 목록·상세를 함께 무효화한다. */
export const communityKeys = {
  all: ["community"] as const,
  feed: (filter: CommunityPostFilter) =>
    [...communityKeys.all, "feed", filter] as const,
  post: (postId: number) => [...communityKeys.all, "post", postId] as const,
};

export function useCommunityFeed(
  filter: CommunityPostFilter = {},
): UseQueryResult<CommunityFeed> {
  return useQuery({
    queryKey: communityKeys.feed(filter),
    queryFn: () => communityRepository.getFeed(filter),
  });
}

export function useCommunityPost(
  postId: number,
): UseQueryResult<CommunityPost | null> {
  return useQuery({
    queryKey: communityKeys.post(postId),
    queryFn: () => communityRepository.getPost(postId),
  });
}

export function useCreateCommunityPost(): UseMutationResult<
  CommunityPost,
  Error,
  CreateCommunityPostInput
> {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (input: CreateCommunityPostInput) =>
      communityRepository.createPost(input),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: communityKeys.all });
    },
  });
}

export function useUpdateCommunityPost(
  postId: number,
): UseMutationResult<CommunityPost, Error, UpdateCommunityPostInput> {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (input: UpdateCommunityPostInput) =>
      communityRepository.updatePost(postId, input),
    onSuccess: (updated) => {
      queryClient.setQueryData(communityKeys.post(postId), updated);
      void queryClient.invalidateQueries({ queryKey: communityKeys.all });
    },
  });
}

export function useDeleteCommunityPost(
  postId: number,
): UseMutationResult<void, Error, void> {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: () => communityRepository.deletePost(postId),
    onSuccess: () => {
      queryClient.removeQueries({ queryKey: communityKeys.post(postId) });
      void queryClient.invalidateQueries({ queryKey: communityKeys.all });
    },
  });
}
