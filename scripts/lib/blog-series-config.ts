export interface BlogSeriesConfig {
  readonly id: string;
  readonly name: string;
  readonly icon: string;
  readonly author: string;
  readonly baseUrl: string;
  readonly priorityUser: string | undefined;
  readonly navLink: string;
}

const AUTO_BLOG_ZERO: BlogSeriesConfig = {
  id: "auto-blog-zero",
  name: "Auto Blog Zero",
  icon: "🤖",
  author: "[[auto-blog-zero]]",
  baseUrl: "https://bagrounds.org/auto-blog-zero",
  priorityUser: "bagrounds",
  navLink: "[[index|Home]] > [[auto-blog-zero/index|🤖 Auto Blog Zero]]",
};

const CHICKIE_LOO: BlogSeriesConfig = {
  id: "chickie-loo",
  name: "Chickie Loo",
  icon: "🐔",
  author: "[[chickie-loo]]",
  baseUrl: "https://bagrounds.org/chickie-loo",
  priorityUser: undefined,
  navLink: "[[index|Home]] > [[chickie-loo/index|🐔 Chickie Loo]]",
};

export const BLOG_SERIES: ReadonlyMap<string, BlogSeriesConfig> = new Map([
  [AUTO_BLOG_ZERO.id, AUTO_BLOG_ZERO],
  [CHICKIE_LOO.id, CHICKIE_LOO],
]);

export const lookupSeries = (seriesId: string): BlogSeriesConfig => {
  const series = BLOG_SERIES.get(seriesId);
  if (!series) throw new Error(`Unknown blog series: ${seriesId}. Available: ${[...BLOG_SERIES.keys()].join(", ")}`);
  return series;
};
