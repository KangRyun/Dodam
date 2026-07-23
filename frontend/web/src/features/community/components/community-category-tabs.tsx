import Link from "next/link";

import type { CommunityPostCategory } from "@/features/community/domain/community-models";

type CommunityCategoryTabsProps = {
  selectedCategory?: CommunityPostCategory;
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
}: CommunityCategoryTabsProps) {
  return (
    <div className="community-category-tabs">
      {categories.map(({ label, value }) => {
        const selected = selectedCategory === value;
        const href =
          value === undefined
            ? "/community"
            : `/community?category=${value}`;

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
