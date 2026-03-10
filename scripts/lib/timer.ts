/**
 * Pipeline timing instrumentation.
 *
 * Records start/end of named phases and prints a summary table.
 * Uses a functional internal representation (append-only array).
 *
 * @module timer
 */

interface TimerEntry {
  readonly name: string;
  readonly startMs: number;
  endMs?: number;
}

const formatDuration = (ms: number): string => (ms / 1000).toFixed(1);
const formatPercent = (part: number, whole: number): string =>
  whole > 0 ? ((part / whole) * 100).toFixed(1) : "0.0";

export class PipelineTimer {
  private entries: TimerEntry[] = [];
  private pipelineStartMs = Date.now();

  start(name: string): void {
    this.entries.push({ name, startMs: Date.now() });
  }

  end(name: string): void {
    const entry = this.entries.find((e) => e.name === name && !e.endMs);
    if (entry) entry.endMs = Date.now();
  }

  async time<T>(name: string, fn: () => Promise<T>): Promise<T> {
    this.start(name);
    try {
      return await fn();
    } finally {
      this.end(name);
    }
  }

  printSummary(): void {
    const totalMs = Date.now() - this.pipelineStartMs;
    const separator = "─".repeat(52);
    console.log(`\n⏱️  Pipeline Timing Summary:`);
    console.log(separator);
    for (const entry of this.entries) {
      const durationMs = (entry.endMs ?? Date.now()) - entry.startMs;
      const pct = formatPercent(durationMs, totalMs);
      const status = entry.endMs ? "✅" : "⏳";
      console.log(
        `  ${status} ${entry.name.padEnd(30)} ${formatDuration(durationMs).padStart(7)}s  (${pct.padStart(5)}%)`,
      );
    }
    console.log(separator);
    console.log(`  🏁 Total pipeline time${" ".repeat(13)} ${formatDuration(totalMs)}s`);
  }
}
