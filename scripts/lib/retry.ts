/**
 * Generic retry utility with exponential backoff.
 *
 * Implements the retry pattern as a higher-order function:
 * wraps any async operation with configurable retry behavior
 * for transient HTTP errors.
 *
 * @module retry
 */

/** HTTP status codes that indicate a transient server error worth retrying. */
const TRANSIENT_HTTP_CODES: ReadonlySet<number> = new Set([429, 502, 503, 504]);

interface RetryOptions {
  readonly maxRetries?: number;
  readonly baseDelayMs?: number;
  readonly onRetry?: (error: unknown, attempt: number, delayMs: number) => void;
}

const extractHttpCode = (err: unknown): number | undefined =>
  typeof err === "object" && err !== null && "code" in err
    ? (err as { code: number }).code
    : undefined;

const isTransientError = (err: unknown): boolean => {
  const code = extractHttpCode(err);
  return code !== undefined && TRANSIENT_HTTP_CODES.has(code);
};

const delay = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Retry an async operation with exponential backoff for transient errors.
 * Only retries when the error has an HTTP `code` in TRANSIENT_HTTP_CODES.
 *
 * This is a higher-order function: it transforms a fallible async function
 * into a more resilient one by wrapping it with retry logic.
 */
export async function withRetry<T>(
  fn: () => Promise<T>,
  {
    maxRetries = 3,
    baseDelayMs = 1000,
    onRetry,
  }: RetryOptions = {},
): Promise<T> {
  let lastError: unknown;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (err: unknown) {
      lastError = err;
      if (attempt < maxRetries && isTransientError(err)) {
        const delayMs = baseDelayMs * 2 ** attempt;
        onRetry?.(err, attempt + 1, delayMs);
        await delay(delayMs);
      } else {
        throw err;
      }
    }
  }
  throw lastError;
}

export { TRANSIENT_HTTP_CODES, extractHttpCode, isTransientError };
