import Link from "next/link";

import type { CommunityPostCategory } from "@/features/community/domain/community-models";

type CommunityCategoryTabsProps = {
  selectedCategory?: CommunityPostCategory;
  query?: string;
  sort?: string;
};

const categories: ReadonlyArray<{
  label: string;
  value?: CommunityPostCategory;
}> = [
  { label: "전체" },
  { label: "보호자 이야기", value: "GUARDIAN_STORY" },
  { label: "칼럼", value: "EXPERT_COLUMN" },
  { label: "전문가 Q&A", value: "EXPERT_QNA" },
  { label: "공지", value: "NOTICE" },
];

const categoryValues = new Set(
  categories.flatMap(({ value }) => (value === undefined ? [] : [value])),
);

export function parseCommunityCategory(
  value?: string,
): CommunityPostCategory | undefined {
  return categoryValues.has(value as CommunityPostCategory)
    ? (value as CommunityPostCategory)
    : undefined;
}

export function CommunityCategoryTabs({
  selectedCategory,
  query,
  sort,
}: CommunityCategoryTabsProps) {
  return (
    <div className="community-category-tabs">
      {categories.map(({ label, value }) => {
        const selected = selectedCategory === value;
        const params = new URLSearchParams();
        if (value) params.set("category", value);
        if (query) params.set("query", query);
        if (sort) params.set("sort", sort);
        const href = `/community${params.size > 0 ? `?${params}` : ""}`;

        return (
          <Link
            key={label}
            className="community-category-tab"
            data-selected={selected}
            aria-current={selected ? "page" : undefined}
            href={href}
            scroll={false}
          >
            {label}
          </Link>
        );
      })}
    </div>
  );
}
