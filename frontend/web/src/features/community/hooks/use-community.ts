"use client";

import {
  useMutation,
  useQuery,
  useQueryClient,
  type UseMutationResult,
  type UseQueryResult,
} from "@tanstack/react-query";

import { communityRepository } from "@/features/community/data/community-repository-factory";
import { createCommunityComplaint } from "@/features/community/data/api/community-complaint-api";
import type {
  CommunityComment,
  CommunityFeed,
  CommunityPost,
  CommunityPostFilter,
  CreateCommunityComplaintInput,
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
  myPosts: () => [...communityKeys.all, "my-posts"] as const,
  likedPosts: () => [...communityKeys.all, "liked-posts"] as const,
};

export function useCommunityFeed(
  filter: CommunityPostFilter = {},
): UseQueryResult<CommunityFeed> {
  return useQuery({
    queryKey: communityKeys.feed(filter),
    queryFn: () => communityRepository.getFeed(filter),
  });
}

export function useCommunityPersonalPosts(
  mode: "mine" | "liked",
): UseQueryResult<CommunityFeed> {
  return useQuery({
    queryKey:
      mode === "mine" ? communityKeys.myPosts() : communityKeys.likedPosts(),
    queryFn: () =>
      mode === "mine"
        ? communityRepository.getMyPosts()
        : communityRepository.getLikedPosts(),
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

type ToggleLikeVariables = {
  liked: boolean;
};

/** 좋아요 상태를 즉시 반영하고 요청 실패 시 이전 상세 데이터로 복구한다. */
export function useToggleCommunityPostLike(
  postId: number,
): UseMutationResult<void, Error, ToggleLikeVariables, CommunityPost | null> {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ liked }) => {
      if (liked) {
        await communityRepository.unlikePost(postId);
      } else {
        await communityRepository.likePost(postId);
      }
    },
    onMutate: async ({ liked }) => {
      await queryClient.cancelQueries({ queryKey: communityKeys.post(postId) });
      const previous =
        queryClient.getQueryData<CommunityPost | null>(
          communityKeys.post(postId),
        ) ?? null;
      queryClient.setQueryData<CommunityPost | null>(
        communityKeys.post(postId),
        (current) =>
          current
            ? {
                ...current,
                isLiked: !liked,
                likeCount: Math.max(0, current.likeCount + (liked ? -1 : 1)),
              }
            : current,
      );
      return previous;
    },
    onError: (_error, _variables, previous) => {
      queryClient.setQueryData(communityKeys.post(postId), previous);
    },
    onSettled: () => {
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

/** COMM-11 신고는 Mock 저장소를 거치지 않고 실제 공통 신고 API로 제출한다. */
export function useCreateCommunityComplaint(): UseMutationResult<
  void,
  Error,
  CreateCommunityComplaintInput
> {
  return useMutation({
    mutationFn: createCommunityComplaint,
  });
}
