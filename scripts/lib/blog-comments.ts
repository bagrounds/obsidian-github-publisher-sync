export interface BlogComment {
  readonly author: string;
  readonly body: string;
  readonly createdAt: string;
  readonly isPriority: boolean;
}

const GISCUS_REPO = "bagrounds/obsidian-github-publisher-sync";

interface GqlDiscussionComment {
  readonly body: string;
  readonly author: { readonly login: string } | null;
  readonly createdAt: string;
}

interface GqlDiscussion {
  readonly title: string;
  readonly comments: { readonly nodes: readonly GqlDiscussionComment[] };
}

interface GqlSearchResult {
  readonly data?: { readonly search: { readonly nodes: readonly GqlDiscussion[] } };
  readonly errors?: ReadonlyArray<{ readonly message: string }>;
}

const toComment = (priorityUser: string | undefined) => (c: GqlDiscussionComment): BlogComment => ({
  author: c.author?.login ?? "unknown",
  body: c.body,
  createdAt: c.createdAt.split("T")[0] as string,
  isPriority: priorityUser !== undefined && c.author?.login === priorityUser,
});

const searchDiscussions = async (
  token: string,
  searchQuery: string,
  maxResults: number,
  maxComments: number,
): Promise<readonly GqlDiscussion[]> => {
  const query = `query($searchQuery: String!) {
    search(type: DISCUSSION, query: $searchQuery, first: ${maxResults}) {
      nodes { ... on Discussion { title, comments(first: ${maxComments}) { nodes { body, author { login }, createdAt } } } }
    }
  }`;

  const response = await fetch("https://api.github.com/graphql", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ query, variables: { searchQuery } }),
  });

  if (!response.ok) {
    console.warn(JSON.stringify({ event: "graphql_error", status: response.status }));
    return [];
  }
  const result = (await response.json()) as GqlSearchResult;
  if (result.errors) {
    console.warn(JSON.stringify({ event: "graphql_errors", errors: result.errors.map((e) => e.message) }));
    return [];
  }
  return result.data?.search?.nodes ?? [];
};

export const fetchGiscusComments = async (
  pathname: string,
  priorityUser: string | undefined,
): Promise<BlogComment[]> => {
  const token = process.env.GITHUB_TOKEN;
  if (!token) {
    console.log(JSON.stringify({ event: "skip_giscus", reason: "no GITHUB_TOKEN" }));
    return [];
  }
  try {
    const discussions = await searchDiscussions(token, `repo:${GISCUS_REPO} in:title "${pathname}"`, 1, 100);
    return (discussions[0]?.comments?.nodes ?? []).map(toComment(priorityUser));
  } catch (error) {
    console.warn(JSON.stringify({ event: "giscus_error", message: error instanceof Error ? error.message : String(error) }));
    return [];
  }
};

export const fetchAllSeriesComments = async (
  seriesId: string,
  priorityUser: string | undefined,
): Promise<BlogComment[]> => {
  const token = process.env.GITHUB_TOKEN;
  if (!token) {
    console.log(JSON.stringify({ event: "skip_giscus", reason: "no GITHUB_TOKEN" }));
    return [];
  }
  try {
    const discussions = await searchDiscussions(token, `repo:${GISCUS_REPO} in:title "${seriesId}/"`, 50, 50);
    return discussions
      .flatMap((d) => (d.comments?.nodes ?? []).map(toComment(priorityUser)))
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  } catch (error) {
    console.warn(JSON.stringify({ event: "giscus_error", message: error instanceof Error ? error.message : String(error) }));
    return [];
  }
};
