export interface BlogSeriesConfig {
  readonly id: string;
  readonly name: string;
  readonly icon: string;
  readonly author: string;
  readonly baseUrl: string;
  readonly priorityUser: string | undefined;
  readonly navLink: string;
  readonly postTimeUtc: string;
}

const AUTO_BLOG_ZERO: BlogSeriesConfig = {
  id: "auto-blog-zero",
  name: "Auto Blog Zero",
  icon: "🤖",
  author: "[[auto-blog-zero]]",
  baseUrl: "https://bagrounds.org/auto-blog-zero",
  priorityUser: "bagrounds",
  navLink: "[[index|Home]] > [[auto-blog-zero/index|🤖 Auto Blog Zero]]",
  postTimeUtc: "16:00",
};

const CHICKIE_LOO: BlogSeriesConfig = {
  id: "chickie-loo",
  name: "Chickie Loo",
  icon: "🐔",
  author: "[[chickie-loo]]",
  baseUrl: "https://bagrounds.org/chickie-loo",
  priorityUser: "ChickieLoo",
  navLink: "[[index|Home]] > [[chickie-loo/index|🐔 Chickie Loo]]",
  postTimeUtc: "15:00",
};

const THE_PUBLIC_GOOD: BlogSeriesConfig = {
  id: "the-public-good",
  name: "The Public Good",
  icon: "🏛️",
  author: "[[the-public-good]]",
  baseUrl: "https://bagrounds.org/the-public-good",
  priorityUser: "bagrounds",
  navLink: "[[index|Home]] > [[the-public-good/index|🏛️ The Public Good]]",
  postTimeUtc: "17:00",
};

export const BLOG_SERIES: ReadonlyMap<string, BlogSeriesConfig> = new Map([
  [AUTO_BLOG_ZERO.id, AUTO_BLOG_ZERO],
  [CHICKIE_LOO.id, CHICKIE_LOO],
  [THE_PUBLIC_GOOD.id, THE_PUBLIC_GOOD],
]);

export const lookupSeries = (seriesId: string): BlogSeriesConfig => {
  const series = BLOG_SERIES.get(seriesId);
  if (!series) throw new Error(`Unknown blog series: ${seriesId}. Available: ${[...BLOG_SERIES.keys()].join(", ")}`);
  return series;
};
