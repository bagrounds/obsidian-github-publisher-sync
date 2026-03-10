/**
 * Pure HTML and date formatting utilities.
 *
 * These functions have no side effects and no external dependencies.
 * They follow the functional principle of referential transparency:
 * calling with the same input always produces the same output.
 *
 * @module html
 */

const HTML_ESCAPE_MAP: ReadonlyMap<string, string> = new Map([
  ["&", "&amp;"],
  ["<", "&lt;"],
  [">", "&gt;"],
  ['"', "&quot;"],
  ["'", "&#39;"],
]);

const HTML_ESCAPE_PATTERN = /[&<>"']/g;

const MONTH_NAMES: readonly string[] = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

/**
 * Escape HTML special characters in text.
 *
 * This is a pure function implementing the HTML character entity mapping:
 *   & → &amp;   < → &lt;   > → &gt;   " → &quot;   ' → &#39;
 */
export const escapeHtml = (text: string): string =>
  text.replace(HTML_ESCAPE_PATTERN, (ch) => HTML_ESCAPE_MAP.get(ch) ?? ch);

/**
 * Convert plain text to HTML-safe text with line breaks.
 * Composes escapeHtml with newline-to-br conversion.
 */
export const textToHtml = (text: string): string =>
  escapeHtml(text).replace(/\n/g, "<br>");

/**
 * Format a YYYY-MM-DD date string for display (e.g. "March 10, 2026").
 * Pure function — no Date.now() or locale dependency.
 */
export const formatDisplayDate = (date: string): string => {
  const dateObj = new Date(date + "T00:00:00Z");
  const month = MONTH_NAMES[dateObj.getUTCMonth()] ?? "Unknown";
  return `${month} ${dateObj.getUTCDate()}, ${dateObj.getUTCFullYear()}`;
};

export { MONTH_NAMES };
