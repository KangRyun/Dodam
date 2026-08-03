export const COMMUNITY_COMPACT_FEED_KEY = "dodam.community.compactFeed";
export const COMMUNITY_PREFERENCE_EVENT = "dodam-community-preference";

export function readCompactFeedPreference(): boolean {
  return (
    typeof window !== "undefined" &&
    window.localStorage.getItem(COMMUNITY_COMPACT_FEED_KEY) === "1"
  );
}

export function subscribeCommunityPreference(onChange: () => void) {
  window.addEventListener("storage", onChange);
  window.addEventListener(COMMUNITY_PREFERENCE_EVENT, onChange);
  return () => {
    window.removeEventListener("storage", onChange);
    window.removeEventListener(COMMUNITY_PREFERENCE_EVENT, onChange);
  };
}

export function writeCompactFeedPreference(compact: boolean) {
  window.localStorage.setItem(COMMUNITY_COMPACT_FEED_KEY, compact ? "1" : "0");
  window.dispatchEvent(new Event(COMMUNITY_PREFERENCE_EVENT));
}
