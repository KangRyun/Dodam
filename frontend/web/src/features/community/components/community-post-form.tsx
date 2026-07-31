"use client";

import { useRouter } from "next/navigation";
import { useForm, useWatch } from "react-hook-form";

import {
  categoryLabels,
  writablePostCategories,
} from "@/features/community/community-category";
import type {
  CommunityPostCategory,
  CreateCommunityPostInput,
} from "@/features/community/domain/community-models";

const TITLE_MAX = 200;
const CONTENT_MAX = 20000;

type CommunityPostFormValues = {
  postType: CommunityPostCategory;
  title: string;
  content: string;
  anonymous: boolean;
};

type CommunityPostFormProps = {
  /** 화면 제목 (예: "글쓰기", "글 수정"). */
  heading: string;
  submitLabel: string;
  defaultValues?: Partial<CommunityPostFormValues>;
  pending: boolean;
  errorMessage?: string;
  onSubmit: (input: CreateCommunityPostInput) => void;
};

export function CommunityPostForm({
  heading,
  submitLabel,
  defaultValues,
  pending,
  errorMessage,
  onSubmit,
}: CommunityPostFormProps) {
  const router = useRouter();
  const {
    register,
    handleSubmit,
    control,
    formState: { errors },
  } = useForm<CommunityPostFormValues>({
    defaultValues: {
      postType: defaultValues?.postType ?? "GUARDIAN_STORY",
      title: defaultValues?.title ?? "",
      content: defaultValues?.content ?? "",
      anonymous: defaultValues?.anonymous ?? false,
    },
  });

  const contentLength =
    useWatch({ control, name: "content" })?.length ?? 0;

  const submit = handleSubmit((values) => {
    onSubmit({
      postType: values.postType,
      title: values.title.trim(),
      content: values.content.trim(),
      anonymous: values.anonymous,
    });
  });

  return (
    <form className="community-post-form" onSubmit={submit} noValidate>
      <div className="community-form-header">
        <h1>{heading}</h1>
        <p>아이의 이름·학교·연락처 등 개인정보는 작성하지 말아 주세요.</p>
      </div>

      <label className="community-field">
        <span className="community-field-label">유형</span>
        <select
          className="community-field-control"
          {...register("postType", { required: true })}
        >
          {writablePostCategories.map((category) => (
            <option key={category} value={category}>
              {categoryLabels[category]}
            </option>
          ))}
        </select>
      </label>

      <label className="community-field">
        <span className="community-field-label">제목</span>
        <input
          className="community-field-control"
          type="text"
          placeholder="제목을 입력해주세요"
          aria-invalid={errors.title ? "true" : undefined}
          {...register("title", {
            required: "제목을 입력해주세요.",
            maxLength: {
              value: TITLE_MAX,
              message: `제목은 ${TITLE_MAX}자까지 입력할 수 있어요.`,
            },
            validate: (value) =>
              value.trim().length > 0 || "제목을 입력해주세요.",
          })}
        />
        {errors.title && (
          <span className="community-field-error" role="alert">
            {errors.title.message}
          </span>
        )}
      </label>

      <label className="community-field">
        <span className="community-field-label">내용</span>
        <textarea
          className="community-field-control community-field-textarea"
          rows={12}
          placeholder="이야기를 자유롭게 들려주세요"
          aria-invalid={errors.content ? "true" : undefined}
          {...register("content", {
            required: "내용을 입력해주세요.",
            maxLength: {
              value: CONTENT_MAX,
              message: `내용은 ${CONTENT_MAX.toLocaleString()}자까지 입력할 수 있어요.`,
            },
            validate: (value) =>
              value.trim().length > 0 || "내용을 입력해주세요.",
          })}
        />
        <span className="community-field-count">
          {contentLength.toLocaleString()} / {CONTENT_MAX.toLocaleString()}
        </span>
        {errors.content && (
          <span className="community-field-error" role="alert">
            {errors.content.message}
          </span>
        )}
      </label>

      <label className="community-field-checkbox">
        <input type="checkbox" {...register("anonymous")} />
        <span>익명으로 작성하기</span>
      </label>

      {errorMessage && (
        <p className="community-form-error" role="alert">
          {errorMessage}
        </p>
      )}

      <div className="community-form-actions">
        <button
          type="button"
          className="community-button community-button-ghost"
          onClick={() => router.back()}
          disabled={pending}
        >
          취소
        </button>
        <button
          type="submit"
          className="community-button community-button-primary"
          disabled={pending}
        >
          {pending ? "저장 중…" : submitLabel}
        </button>
      </div>
    </form>
  );
}
