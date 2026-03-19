/**
 * Gemini API quota and model discovery.
 *
 * Combines three data sources for comprehensive quota observability:
 * 1. Gemini REST API — model catalog (token limits, supported methods)
 * 2. GCP Service Usage API — per-model quota limits (RPM, TPM, RPD)
 * 3. GCP Cloud Monitoring API — real-time usage metrics
 *
 * The Gemini API key provides (1). A GCP service account key provides (2) and (3).
 *
 * @module gemini-quota
 */

import type { ServiceAccountKey } from "./gcp-auth.ts";

const GEMINI_API_BASE = "https://generativelanguage.googleapis.com/v1beta";
const SERVICE_USAGE_BASE = "https://serviceusage.googleapis.com/v1beta1";
const MONITORING_BASE = "https://monitoring.googleapis.com/v3";
const GEMINI_SERVICE = "generativelanguage.googleapis.com";

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

export interface QuotaLimit {
  readonly metric: string;
  readonly displayName: string;
  readonly unit: string;
  readonly effectiveLimit: number;
  readonly defaultLimit: number;
}

export interface UsageMetric {
  readonly metric: string;
  readonly value: number;
  readonly timestamp: string;
}

export interface QuotaReport {
  readonly label: string;
  readonly timestamp: string;
  readonly models: readonly GeminiModelInfo[];
  readonly quotaLimits: readonly QuotaLimit[];
  readonly usage: readonly UsageMetric[];
}

interface RawModelResponse {
  readonly models?: readonly Record<string, unknown>[];
  readonly nextPageToken?: string;
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

export const safeInt = (value: unknown, fallback: number): number => {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
};

// ---------------------------------------------------------------------------
// 1. Gemini model catalog (API key auth)
// ---------------------------------------------------------------------------

const parseModel = (raw: Record<string, unknown>): GeminiModelInfo => ({
  name: String(raw.name ?? ""),
  displayName: String(raw.displayName ?? ""),
  description: String(raw.description ?? ""),
  inputTokenLimit: safeInt(raw.inputTokenLimit, 0),
  outputTokenLimit: safeInt(raw.outputTokenLimit, 0),
  supportedGenerationMethods: Array.isArray(raw.supportedGenerationMethods)
    ? raw.supportedGenerationMethods.filter((x): x is string => typeof x === "string")
    : [],
  ...(raw.temperature != null ? { temperature: safeInt(raw.temperature, 0) } : {}),
  ...(raw.maxTemperature != null ? { maxTemperature: safeInt(raw.maxTemperature, 0) } : {}),
  ...(raw.topP != null ? { topP: safeInt(raw.topP, 0) } : {}),
  ...(raw.topK != null ? { topK: safeInt(raw.topK, 0) } : {}),
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
// 2. Service Usage API — quota limits (service account auth)
// ---------------------------------------------------------------------------

interface RawQuotaBucket {
  readonly effectiveLimit?: string;
  readonly defaultLimit?: string;
}

interface RawConsumerQuotaLimit {
  readonly name?: string;
  readonly unit?: string;
  readonly quotaBuckets?: readonly RawQuotaBucket[];
}

interface RawConsumerQuotaMetric {
  readonly name?: string;
  readonly metric?: string;
  readonly displayName?: string;
  readonly consumerQuotaLimits?: readonly RawConsumerQuotaLimit[];
}

interface RawQuotaMetricsResponse {
  readonly metrics?: readonly RawConsumerQuotaMetric[];
  readonly nextPageToken?: string;
}

const parseQuotaLimits = (raw: RawConsumerQuotaMetric): readonly QuotaLimit[] =>
  (raw.consumerQuotaLimits ?? []).map((limit) => {
    const bucket = (limit.quotaBuckets ?? [])[0];
    return {
      metric: String(raw.metric ?? ""),
      displayName: String(raw.displayName ?? ""),
      unit: String(limit.unit ?? ""),
      effectiveLimit: safeInt(bucket?.effectiveLimit, 0),
      defaultLimit: safeInt(bucket?.defaultLimit, 0),
    };
  });

export const fetchQuotaLimits = async (
  accessToken: string,
  projectId: string,
): Promise<readonly QuotaLimit[]> => {
  const allLimits: QuotaLimit[] = [];
  let pageToken: string | undefined;

  do {
    const url = new URL(
      `${SERVICE_USAGE_BASE}/projects/${projectId}/services/${GEMINI_SERVICE}/consumerQuotaMetrics`,
    );
    url.searchParams.set("pageSize", "100");
    if (pageToken) url.searchParams.set("pageToken", pageToken);

    const response = await fetch(url.toString(), {
      headers: { Authorization: `Bearer ${accessToken}` },
    });

    if (!response.ok) {
      const body = await response.text();
      throw new Error(`Service Usage API ${response.status}: ${body}`);
    }

    const data = (await response.json()) as RawQuotaMetricsResponse;
    const limits = (data.metrics ?? []).flatMap(parseQuotaLimits);
    allLimits.push(...limits);
    pageToken = data.nextPageToken ?? undefined;
  } while (pageToken);

  return allLimits;
};

// ---------------------------------------------------------------------------
// 3. Cloud Monitoring API — real-time usage (service account auth)
// ---------------------------------------------------------------------------

interface RawPoint {
  readonly interval?: {
    readonly startTime?: string;
    readonly endTime?: string;
  };
  readonly value?: {
    readonly int64Value?: string;
    readonly doubleValue?: number;
  };
}

interface RawTimeSeries {
  readonly metric?: {
    readonly type?: string;
    readonly labels?: Record<string, string>;
  };
  readonly points?: readonly RawPoint[];
}

interface RawTimeSeriesResponse {
  readonly timeSeries?: readonly RawTimeSeries[];
  readonly nextPageToken?: string;
}

const parseUsageMetrics = (series: RawTimeSeries): readonly UsageMetric[] =>
  (series.points ?? []).map((point) => ({
    metric: String(series.metric?.type ?? ""),
    value: safeInt(
      point.value?.int64Value ?? point.value?.doubleValue,
      0,
    ),
    timestamp: String(point.interval?.endTime ?? ""),
  }));

const ONE_HOUR_MS = 60 * 60 * 1000;
const ALIGNMENT_PERIOD = "60s";

export const fetchUsageMetrics = async (
  accessToken: string,
  projectId: string,
): Promise<readonly UsageMetric[]> => {
  const now = new Date();
  const oneHourAgo = new Date(now.getTime() - ONE_HOUR_MS);

  const filter = [
    `metric.type = "serviceruntime.googleapis.com/quota/rate/net_usage"`,
    `resource.labels.service = "${GEMINI_SERVICE}"`,
  ].join(" AND ");

  const url = new URL(`${MONITORING_BASE}/projects/${projectId}/timeSeries`);
  url.searchParams.set("filter", filter);
  url.searchParams.set("interval.startTime", oneHourAgo.toISOString());
  url.searchParams.set("interval.endTime", now.toISOString());
  url.searchParams.set("aggregation.alignmentPeriod", ALIGNMENT_PERIOD);
  url.searchParams.set(
    "aggregation.perSeriesAligner",
    "ALIGN_RATE",
  );

  const response = await fetch(url.toString(), {
    headers: { Authorization: `Bearer ${accessToken}` },
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Cloud Monitoring API ${response.status}: ${body}`);
  }

  const data = (await response.json()) as RawTimeSeriesResponse;
  return (data.timeSeries ?? []).flatMap(parseUsageMetrics);
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
// Report building
// ---------------------------------------------------------------------------

export const buildQuotaReport = (
  models: readonly GeminiModelInfo[],
  label: string,
  quotaLimits: readonly QuotaLimit[] = [],
  usage: readonly UsageMetric[] = [],
): QuotaReport => ({
  label,
  timestamp: new Date().toISOString(),
  models,
  quotaLimits,
  usage,
});

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

const formatTokenLimits = (m: GeminiModelInfo): string =>
  `in=${m.inputTokenLimit.toLocaleString()} out=${m.outputTokenLimit.toLocaleString()}`;

const formatModelLine = (m: GeminiModelInfo): string =>
  `  ${m.name.padEnd(45)} ${formatTokenLimits(m).padEnd(28)} [${m.supportedGenerationMethods.join(", ")}]`;

export const formatQuotaLimitLine = (q: QuotaLimit): string =>
  `  ${q.displayName.padEnd(55)} ${String(q.effectiveLimit).padStart(12)} ${q.unit}`;

export const formatUsageLine = (u: UsageMetric): string =>
  `  ${u.metric.padEnd(70)} ${String(u.value).padStart(8)} @ ${u.timestamp}`;

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

  const quotaSection = report.quotaLimits.length > 0
    ? [
        `\n📋 Quota Limits (${report.quotaLimits.length} metrics):`,
        divider,
        ...report.quotaLimits.map(formatQuotaLimitLine),
      ]
    : [];

  const usageSection = report.usage.length > 0
    ? [
        `\n📈 Recent Usage (last hour, ${report.usage.length} data points):`,
        divider,
        ...report.usage.map(formatUsageLine),
      ]
    : [];

  const summary = [
    `\n📊 Summary: ${report.models.length} total models, ${gen.length} generative, ${report.quotaLimits.length} quota metrics, ${report.usage.length} usage data points`,
  ];

  return [header, ...genSection, ...otherSection, ...quotaSection, ...usageSection, ...summary, ""].join("\n");
};

// ---------------------------------------------------------------------------
// Orchestrator — fetch everything available
// ---------------------------------------------------------------------------

export interface QuotaFetchConfig {
  readonly apiKey: string;
  readonly label: string;
  readonly accessToken?: string;
  readonly projectId?: string;
}

const errorMessage = (err: unknown): string =>
  err instanceof Error ? err.message : String(err);

export const fetchFullQuotaReport = async (
  config: QuotaFetchConfig,
): Promise<QuotaReport> => {
  const models = await fetchModels(config.apiKey);

  let quotaLimits: readonly QuotaLimit[] = [];
  let usage: readonly UsageMetric[] = [];

  if (config.accessToken && config.projectId) {
    const [limits, metrics] = await Promise.all([
      fetchQuotaLimits(config.accessToken, config.projectId).catch((err) => {
        console.warn(`⚠️ Service Usage API error (quota limits): ${errorMessage(err)}`);
        return [] as readonly QuotaLimit[];
      }),
      fetchUsageMetrics(config.accessToken, config.projectId).catch((err) => {
        console.warn(`⚠️ Cloud Monitoring API error (usage metrics): ${errorMessage(err)}`);
        return [] as readonly UsageMetric[];
      }),
    ]);
    quotaLimits = limits;
    usage = metrics;
  }

  return buildQuotaReport(models, config.label, quotaLimits, usage);
};
