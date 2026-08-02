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
  CommunityComment,
  CommunityFeed,
  CommunityPost,
  CommunityPostFilter,
  CreateCommunityCommentInput,
  CreateCommunityPostInput,
  UpdateCommunityCommentInput,
  UpdateCommunityPostInput,
} from "@/features/community/domain/community-models";

/** React Query 캐시 키. 게시글 변경 시 관련 목록·상세를 함께 무효화한다. */
export const communityKeys = {
  all: ["community"] as const,
  feed: (filter: CommunityPostFilter) =>
    [...communityKeys.all, "feed", filter] as const,
  post: (postId: number) => [...communityKeys.all, "post", postId] as const,
  comments: (postId: number) =>
    [...communityKeys.all, "comments", postId] as const,
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

export function useCommunityComments(
  postId: number,
): UseQueryResult<readonly CommunityComment[]> {
  return useQuery({
    queryKey: communityKeys.comments(postId),
    queryFn: () => communityRepository.getComments(postId),
  });
}

/** 댓글 수·목록이 함께 바뀌므로 댓글 목록과 게시글 상세를 같이 무효화한다. */
function invalidateComments(
  queryClient: ReturnType<typeof useQueryClient>,
  postId: number,
) {
  void queryClient.invalidateQueries({
    queryKey: communityKeys.comments(postId),
  });
  void queryClient.invalidateQueries({ queryKey: communityKeys.post(postId) });
}

export function useCreateCommunityComment(
  postId: number,
): UseMutationResult<CommunityComment, Error, CreateCommunityCommentInput> {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (input: CreateCommunityCommentInput) =>
      communityRepository.createComment(postId, input),
    onSuccess: () => invalidateComments(queryClient, postId),
  });
}

export function useUpdateCommunityComment(
  postId: number,
): UseMutationResult<
  CommunityComment,
  Error,
  { commentId: number; input: UpdateCommunityCommentInput }
> {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ commentId, input }) =>
      communityRepository.updateComment(commentId, input),
    onSuccess: () => invalidateComments(queryClient, postId),
  });
}

export function useDeleteCommunityComment(
  postId: number,
): UseMutationResult<void, Error, number> {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (commentId: number) =>
      communityRepository.deleteComment(commentId),
    onSuccess: () => invalidateComments(queryClient, postId),
  });
}
