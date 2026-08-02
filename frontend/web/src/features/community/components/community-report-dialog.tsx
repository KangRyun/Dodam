"use client";

import { useEffect, useId, useState } from "react";

import type {
  CommunityComplaintReason,
  CommunityComplaintTargetType,
} from "@/features/community/domain/community-models";
import { useCreateCommunityComplaint } from "@/features/community/hooks/use-community";
import { ApiClientError } from "@/lib/api/api-client";

const DESCRIPTION_MAX = 500;

const reportReasons: ReadonlyArray<{
  code: CommunityComplaintReason;
  label: string;
}> = [
  { code: "INAPPROPRIATE_CONTENT", label: "부적절하거나 불쾌한 내용" },
  { code: "PERSONAL_INFORMATION", label: "개인정보 노출" },
  { code: "MISLEADING_DIAGNOSIS", label: "오해를 부르는 진단·의학 정보" },
  { code: "HARASSMENT", label: "괴롭힘·비방" },
  { code: "COPYRIGHT", label: "저작권 침해" },
  { code: "OTHER", label: "기타" },
];

export type CommunityReportTarget = {
  type: CommunityComplaintTargetType;
  id: number;
};

export function CommunityReportDialog({
  target,
  onClose,
}: {
  target: CommunityReportTarget;
  onClose: () => void;
}) {
  const titleId = useId();
  const complaint = useCreateCommunityComplaint();
  const [reason, setReason] = useState<CommunityComplaintReason | null>(null);
  const [description, setDescription] = useState("");

  useEffect(() => {
    const closeWithEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !complaint.isPending) onClose();
    };
    window.addEventListener("keydown", closeWithEscape);
    return () => window.removeEventListener("keydown", closeWithEscape);
  }, [complaint.isPending, onClose]);

  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    if (reason === null || complaint.isPending) return;
    const trimmed = description.trim();
    complaint.mutate({
      targetType: target.type,
      targetId: target.id,
      reasonCode: reason,
      ...(trimmed.length > 0 ? { description: trimmed } : {}),
    });
  };

  const errorMessage = complaint.isError
    ? complaint.error instanceof ApiClientError &&
      complaint.error.code === "COMPLAINT_ALREADY_EXISTS"
      ? "이미 같은 사유로 신고한 내용이에요."
      : complaint.error.message || "신고를 접수하지 못했어요. 다시 시도해 주세요."
    : null;

  return (
    <div
      className="community-report-backdrop"
      role="presentation"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget && !complaint.isPending) onClose();
      }}
    >
      <section
        className="community-report-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
      >
        {complaint.isSuccess ? (
          <div className="community-report-success">
            <span aria-hidden="true">✓</span>
            <h2 id={titleId}>신고가 접수됐어요</h2>
            <p>운영팀이 내용을 확인한 뒤 안전하게 처리할게요.</p>
            <button
              type="button"
              className="community-button community-button-primary"
              onClick={onClose}
            >
              확인
            </button>
          </div>
        ) : (
          <form onSubmit={submit}>
            <header className="community-report-header">
              <div>
                <h2 id={titleId}>
                  {target.type === "POST" ? "게시글" : "댓글"} 신고하기
                </h2>
                <p>신고 사유를 선택해 주세요.</p>
              </div>
              <button
                type="button"
                aria-label="신고 창 닫기"
                onClick={onClose}
                disabled={complaint.isPending}
              >
                ×
              </button>
            </header>

            <fieldset className="community-report-reasons">
              <legend className="sr-only">신고 사유</legend>
              {reportReasons.map((item) => (
                <label key={item.code}>
                  <input
                    type="radio"
                    name="report-reason"
                    value={item.code}
                    checked={reason === item.code}
                    onChange={() => setReason(item.code)}
                    disabled={complaint.isPending}
                  />
                  <span>{item.label}</span>
                </label>
              ))}
            </fieldset>

            <label className="community-report-description">
              <span>상세 내용 <small>(선택)</small></span>
              <textarea
                rows={3}
                maxLength={DESCRIPTION_MAX}
                placeholder="운영팀이 확인할 내용을 적어 주세요."
                value={description}
                onChange={(event) => setDescription(event.target.value)}
                disabled={complaint.isPending}
              />
              <small>{description.length}/{DESCRIPTION_MAX}</small>
            </label>

            {errorMessage && (
              <p className="community-report-error" role="alert">
                {errorMessage}
              </p>
            )}

            <div className="community-report-actions">
              <button
                type="button"
                className="community-button community-button-ghost"
                onClick={onClose}
                disabled={complaint.isPending}
              >
                취소
              </button>
              <button
                type="submit"
                className="community-button community-button-primary"
                disabled={reason === null || complaint.isPending}
              >
                {complaint.isPending ? "접수 중…" : "신고하기"}
              </button>
            </div>
          </form>
        )}
      </section>
    </div>
  );
}
