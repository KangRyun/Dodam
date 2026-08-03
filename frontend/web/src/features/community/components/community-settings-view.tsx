"use client";

import Link from "next/link";
import { useSyncExternalStore } from "react";

import { CommunityShell } from "@/features/community/components/community-shell";
import {
  readCompactFeedPreference,
  subscribeCommunityPreference,
  writeCompactFeedPreference,
} from "@/features/community/community-preferences";

export function CommunitySettingsView() {
  const compactFeed = useSyncExternalStore(
    subscribeCommunityPreference,
    readCompactFeedPreference,
    () => false,
  );

  const updateCompactFeed = (checked: boolean) => {
    writeCompactFeedPreference(checked);
  };

  return (
    <CommunityShell
      sidebar={null}
      navigation={
        <div className="community-personal-heading">
          <Link href="/community" aria-label="커뮤니티로 돌아가기">←</Link>
          <h1>커뮤니티 설정</h1>
        </div>
      }
    >
      <section className="community-settings-card">
        <div>
          <h2>목록을 간단히 보기</h2>
          <p>게시글 목록에서 핵심 내용 위주로 표시해요.</p>
        </div>
        <label className="community-switch">
          <input
            type="checkbox"
            checked={compactFeed}
            onChange={(event) => updateCompactFeed(event.target.checked)}
          />
          <span aria-hidden="true" />
        </label>
      </section>
      <section className="community-settings-card community-settings-guide">
        <div>
          <h2>알림 설정</h2>
          <p>댓글과 서비스 알림은 도담 앱의 설정에서 관리할 수 있어요.</p>
        </div>
      </section>
    </CommunityShell>
  );
}
