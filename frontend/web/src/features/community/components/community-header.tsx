export function CommunityHeader() {
  return (
    <header className="community-header">
      <div className="community-header-inner">
        <a className="community-brand" href="/community" aria-label="마음그림 커뮤니티 홈">
          <span aria-hidden="true">🖍️</span>
          <span>마음그림 커뮤니티</span>
        </a>

        <label className="community-search">
          <span className="sr-only">커뮤니티 검색</span>
          <span aria-hidden="true">⌕</span>
          <input
            type="search"
            placeholder="관심 있는 이야기를 검색해보세요"
            aria-label="관심 있는 이야기 검색"
          />
        </label>

        <button
          className="community-profile-button"
          type="button"
          aria-label="내 커뮤니티 메뉴"
        >
          🌱
        </button>
      </div>
    </header>
  );
}
