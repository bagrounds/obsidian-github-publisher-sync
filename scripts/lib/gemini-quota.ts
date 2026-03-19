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

export interface UsageDataPoint {
  readonly quotaMetric: string;
  readonly value: number;
  readonly timestamp: string;
  readonly metricType: string;
}

export interface QuotaEntry {
  readonly name: string;
  readonly displayName: string;
  readonly unit: string;
  readonly limit: number;
  readonly used: number | null;
  readonly remaining: number | null;
}

export interface QuotaReport {
  readonly label: string;
  readonly timestamp: string;
  readonly models: readonly GeminiModelInfo[];
  readonly quotaLimits: readonly QuotaLimit[];
  readonly usage: readonly UsageDataPoint[];
  readonly freeTierSummary: readonly QuotaEntry[];
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

const errorMessage = (err: unknown): string =>
  err instanceof Error ? err.message : String(err);

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
  readonly resource?: {
    readonly labels?: Record<string, string>;
  };
  readonly points?: readonly RawPoint[];
}

interface RawTimeSeriesResponse {
  readonly timeSeries?: readonly RawTimeSeries[];
  readonly nextPageToken?: string;
}

const parseUsageDataPoints = (series: RawTimeSeries): readonly UsageDataPoint[] =>
  (series.points ?? []).map((point) => ({
    quotaMetric: String(series.metric?.labels?.quota_metric ?? ""),
    metricType: String(series.metric?.type ?? ""),
    value: safeInt(
      point.value?.int64Value ?? point.value?.doubleValue,
      0,
    ),
    timestamp: String(point.interval?.endTime ?? ""),
  }));

const ONE_HOUR_MS = 60 * 60 * 1000;
const ONE_DAY_MS = 24 * ONE_HOUR_MS;

const fetchMonitoringTimeSeries = async (
  accessToken: string,
  projectId: string,
  metricType: string,
  intervalMs: number,
): Promise<readonly RawTimeSeries[]> => {
  const now = new Date();
  const start = new Date(now.getTime() - intervalMs);

  const filter = [
    `metric.type = "${metricType}"`,
    `resource.labels.service = "${GEMINI_SERVICE}"`,
  ].join(" AND ");

  const url = new URL(`${MONITORING_BASE}/projects/${projectId}/timeSeries`);
  url.searchParams.set("filter", filter);
  url.searchParams.set("interval.startTime", start.toISOString());
  url.searchParams.set("interval.endTime", now.toISOString());

  const response = await fetch(url.toString(), {
    headers: { Authorization: `Bearer ${accessToken}` },
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Cloud Monitoring API ${response.status}: ${body}`);
  }

  const data = (await response.json()) as RawTimeSeriesResponse;
  return data.timeSeries ?? [];
};

export const fetchUsageMetrics = async (
  accessToken: string,
  projectId: string,
): Promise<readonly UsageDataPoint[]> => {
  const [allocationSeries, rateSeries] = await Promise.all([
    fetchMonitoringTimeSeries(
      accessToken,
      projectId,
      "serviceruntime.googleapis.com/quota/allocation/usage",
      ONE_DAY_MS,
    ),
    fetchMonitoringTimeSeries(
      accessToken,
      projectId,
      "serviceruntime.googleapis.com/quota/rate/net_usage",
      ONE_HOUR_MS,
    ),
  ]);

  return [
    ...allocationSeries.flatMap(parseUsageDataPoints),
    ...rateSeries.flatMap(parseUsageDataPoints),
  ];
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

const isFreeTierLimit = (q: QuotaLimit): boolean =>
  q.displayName.toLowerCase().includes("free tier") && q.effectiveLimit > 0;

export const freeTierLimits = (limits: readonly QuotaLimit[]): readonly QuotaLimit[] =>
  limits.filter(isFreeTierLimit);

// ---------------------------------------------------------------------------
// Usage → limit correlation
// ---------------------------------------------------------------------------

const latestValueByQuotaMetric = (
  usage: readonly UsageDataPoint[],
): ReadonlyMap<string, number> => {
  const map = new Map<string, { value: number; timestamp: string }>();
  usage.forEach((point) => {
    const existing = map.get(point.quotaMetric);
    if (!existing || point.timestamp > existing.timestamp) {
      map.set(point.quotaMetric, { value: point.value, timestamp: point.timestamp });
    }
  });
  return new Map([...map.entries()].map(([k, v]) => [k, v.value]));
};

export const buildFreeTierSummary = (
  limits: readonly QuotaLimit[],
  usage: readonly UsageDataPoint[],
): readonly QuotaEntry[] => {
  const usageByMetric = latestValueByQuotaMetric(usage);
  return freeTierLimits(limits).map((q) => {
    const used = usageByMetric.get(q.metric) ?? null;
    return {
      name: q.metric,
      displayName: q.displayName,
      unit: q.unit,
      limit: q.effectiveLimit,
      used,
      remaining: used !== null && q.effectiveLimit > 0
        ? q.effectiveLimit - used
        : null,
    };
  });
};

// ---------------------------------------------------------------------------
// Report building
// ---------------------------------------------------------------------------

export const buildQuotaReport = (
  models: readonly GeminiModelInfo[],
  label: string,
  quotaLimits: readonly QuotaLimit[] = [],
  usage: readonly UsageDataPoint[] = [],
): QuotaReport => ({
  label,
  timestamp: new Date().toISOString(),
  models,
  quotaLimits,
  usage,
  freeTierSummary: buildFreeTierSummary(quotaLimits, usage),
});

// ---------------------------------------------------------------------------
// Formatting — human-readable report
// ---------------------------------------------------------------------------

const formatModelLine = (m: GeminiModelInfo): string => {
  const inTok = m.inputTokenLimit.toLocaleString();
  const outTok = m.outputTokenLimit.toLocaleString();
  return `  ${m.name.padEnd(52)} in=${inTok.padStart(10)}  out=${outTok.padStart(8)}`;
};

const formatUsedOfLimit = (used: number | null, limit: number): string =>
  used !== null ? `${used} / ${limit}` : `? / ${limit}`;

export const formatQuotaEntry = (q: QuotaEntry): string => {
  const usage = formatUsedOfLimit(q.used, q.limit);
  return `  ${q.displayName.padEnd(68)} ${usage.padStart(14)}  ${q.unit}`;
};

export const formatQuotaReport = (report: QuotaReport): string => {
  const header = `\n🔍 Gemini Quota Report — ${report.label}\n⏰ ${report.timestamp}`;

  const gen = generativeModels(report.models);
  const other = report.models.filter(
    (m) => !m.supportedGenerationMethods.includes("generateContent"),
  );

  // --- Free tier summary (the main useful section) ---
  const freeTierSection = report.freeTierSummary.length > 0
    ? [
        `\n📊 Free Tier Quota — Used / Limit`,
        "─".repeat(100),
        ...report.freeTierSummary.map(formatQuotaEntry),
      ]
    : report.quotaLimits.length > 0
      ? [`\n📊 Free Tier Quota: no free tier limits found in ${report.quotaLimits.length} quota metrics`]
      : [];

  // --- Usage data diagnostics ---
  const usageNote = report.usage.length > 0
    ? [`\n📈 ${report.usage.length} usage data points from Cloud Monitoring`]
    : report.quotaLimits.length > 0
      ? [`\n📈 Usage: no data points from Cloud Monitoring (usage may take a few minutes to appear)`]
      : [];

  // --- Model catalog (compact) ---
  const genSection = gen.length > 0
    ? [`\n📝 Content-generation models (${gen.length}):`, "─".repeat(100), ...gen.map(formatModelLine)]
    : [];

  const otherSection = other.length > 0
    ? [`\n🔧 Other models (${other.length}):`, "─".repeat(100), ...other.map(formatModelLine)]
    : [];

  const summary = [
    `\n📋 Summary: ${report.models.length} models (${gen.length} generative), ${report.freeTierSummary.length} free tier quotas tracked, ${report.usage.length} usage data points`,
  ];

  return [header, ...freeTierSection, ...usageNote, ...genSection, ...otherSection, ...summary, ""].join("\n");
};

// ---------------------------------------------------------------------------
// JSON output — structured for programmatic use
// ---------------------------------------------------------------------------

export interface QuotaJson {
  readonly label: string;
  readonly timestamp: string;
  readonly freeTierQuotas: readonly QuotaEntry[];
  readonly generativeModels: readonly {
    readonly name: string;
    readonly displayName: string;
    readonly inputTokenLimit: number;
    readonly outputTokenLimit: number;
  }[];
  readonly allQuotaLimits: readonly QuotaLimit[];
  readonly usageDataPoints: readonly UsageDataPoint[];
}

export const toQuotaJson = (report: QuotaReport): QuotaJson => ({
  label: report.label,
  timestamp: report.timestamp,
  freeTierQuotas: report.freeTierSummary,
  generativeModels: generativeModels(report.models).map((m) => ({
    name: m.name,
    displayName: m.displayName,
    inputTokenLimit: m.inputTokenLimit,
    outputTokenLimit: m.outputTokenLimit,
  })),
  allQuotaLimits: report.quotaLimits,
  usageDataPoints: report.usage,
});

// ---------------------------------------------------------------------------
// Orchestrator — fetch everything available
// ---------------------------------------------------------------------------

export interface QuotaFetchConfig {
  readonly apiKey: string;
  readonly label: string;
  readonly accessToken?: string;
  readonly projectId?: string;
}

export const fetchFullQuotaReport = async (
  config: QuotaFetchConfig,
): Promise<QuotaReport> => {
  const models = await fetchModels(config.apiKey);

  let quotaLimits: readonly QuotaLimit[] = [];
  let usage: readonly UsageDataPoint[] = [];

  if (config.accessToken && config.projectId) {
    const [limits, metrics] = await Promise.all([
      fetchQuotaLimits(config.accessToken, config.projectId).catch((err) => {
        console.warn(`⚠️ Service Usage API error (quota limits): ${errorMessage(err)}`);
        return [] as readonly QuotaLimit[];
      }),
      fetchUsageMetrics(config.accessToken, config.projectId).catch((err) => {
        console.warn(`⚠️ Cloud Monitoring API error (usage metrics): ${errorMessage(err)}`);
        return [] as readonly UsageDataPoint[];
      }),
    ]);
    quotaLimits = limits;
    usage = metrics;
  }

  return buildQuotaReport(models, config.label, quotaLimits, usage);
};
