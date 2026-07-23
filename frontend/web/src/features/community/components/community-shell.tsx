import type { ReactNode } from "react";

import { CommunityHeader } from "@/features/community/components/community-header";

type CommunityShellProps = {
  children: ReactNode;
  navigation: ReactNode;
  sidebar: ReactNode;
};

export function CommunityShell({
  children,
  navigation,
  sidebar,
}: CommunityShellProps) {
  return (
    <div className="community-page">
      <CommunityHeader />
      <main className="community-main">
        <div className="community-feed-column">
          <nav aria-label="게시글 카테고리">{navigation}</nav>
          <div className="community-feed">{children}</div>
        </div>
        <aside className="community-sidebar" aria-label="커뮤니티 보조 정보">
          {sidebar}
        </aside>
      </main>
    </div>
  );
}
