/**
 * Gemini API quota and model discovery.
 *
 * Lists available models and their metadata (token limits, rate limits,
 * supported actions) via the generativelanguage REST API.
 *
 * @module gemini-quota
 */

const GEMINI_API_BASE = "https://generativelanguage.googleapis.com/v1beta";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface GeminiModelInfo {
  readonly name: string;
  readonly displayName: string;
  readonly description: string;
  readonly inputTokenLimit: number;
  readonly outputTokenLimit: number;
  readonly supportedGenerationMethods: readonly string[];
  readonly temperature?: number;
  readonly maxTemperature?: number;
  readonly topP?: number;
  readonly topK?: number;
}

export interface QuotaReport {
  readonly label: string;
  readonly timestamp: string;
  readonly models: readonly GeminiModelInfo[];
}

interface RawModelResponse {
  readonly models?: readonly Record<string, unknown>[];
  readonly nextPageToken?: string;
}

// ---------------------------------------------------------------------------
// API interaction
// ---------------------------------------------------------------------------

const parseModel = (raw: Record<string, unknown>): GeminiModelInfo => ({
  name: String(raw.name ?? ""),
  displayName: String(raw.displayName ?? ""),
  description: String(raw.description ?? ""),
  inputTokenLimit: Number(raw.inputTokenLimit ?? 0),
  outputTokenLimit: Number(raw.outputTokenLimit ?? 0),
  supportedGenerationMethods: Array.isArray(raw.supportedGenerationMethods)
    ? (raw.supportedGenerationMethods as string[])
    : [],
  ...(raw.temperature != null ? { temperature: Number(raw.temperature) } : {}),
  ...(raw.maxTemperature != null ? { maxTemperature: Number(raw.maxTemperature) } : {}),
  ...(raw.topP != null ? { topP: Number(raw.topP) } : {}),
  ...(raw.topK != null ? { topK: Number(raw.topK) } : {}),
});

const fetchPage = async (
  apiKey: string,
  pageToken?: string,
): Promise<RawModelResponse> => {
  const url = new URL(`${GEMINI_API_BASE}/models`);
  url.searchParams.set("key", apiKey);
  url.searchParams.set("pageSize", "100");
  if (pageToken) url.searchParams.set("pageToken", pageToken);

  const response = await fetch(url.toString());
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Gemini models API ${response.status}: ${body}`);
  }
  return (await response.json()) as RawModelResponse;
};

export const fetchModels = async (apiKey: string): Promise<readonly GeminiModelInfo[]> => {
  const allModels: GeminiModelInfo[] = [];
  let pageToken: string | undefined;

  do {
    const page = await fetchPage(apiKey, pageToken);
    const models = (page.models ?? []).map(parseModel);
    allModels.push(...models);
    pageToken = page.nextPageToken ?? undefined;
  } while (pageToken);

  return allModels;
};

// ---------------------------------------------------------------------------
// Filtering
// ---------------------------------------------------------------------------

export const generativeModels = (
  models: readonly GeminiModelInfo[],
): readonly GeminiModelInfo[] =>
  models.filter((m) =>
    m.supportedGenerationMethods.includes("generateContent"),
  );

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

const formatTokenLimits = (m: GeminiModelInfo): string =>
  `in=${m.inputTokenLimit.toLocaleString()} out=${m.outputTokenLimit.toLocaleString()}`;

const formatModelLine = (m: GeminiModelInfo): string =>
  `  ${m.name.padEnd(45)} ${formatTokenLimits(m).padEnd(28)} [${m.supportedGenerationMethods.join(", ")}]`;

export const buildQuotaReport = (
  models: readonly GeminiModelInfo[],
  label: string,
): QuotaReport => ({
  label,
  timestamp: new Date().toISOString(),
  models,
});

export const formatQuotaReport = (report: QuotaReport): string => {
  const header = `\n🔍 Gemini Quota Report — ${report.label}\n⏰ ${report.timestamp}`;
  const divider = "─".repeat(100);

  const gen = generativeModels(report.models);
  const other = report.models.filter(
    (m) => !m.supportedGenerationMethods.includes("generateContent"),
  );

  const genSection = gen.length > 0
    ? [`\n📝 Content-generation models (${gen.length}):`, divider, ...gen.map(formatModelLine)]
    : [];

  const otherSection = other.length > 0
    ? [`\n🔧 Other models (${other.length}):`, divider, ...other.map(formatModelLine)]
    : [];

  const summary = [
    `\n📊 Summary: ${report.models.length} total models, ${gen.length} generative`,
  ];

  return [header, ...genSection, ...otherSection, ...summary, ""].join("\n");
};
