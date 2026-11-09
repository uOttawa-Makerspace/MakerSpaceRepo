import { randomBytes } from "node:crypto";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { afterAll, afterEach, vi } from "vitest";

// Fake timers never outlive the example that turned them on, even when it fails.
afterEach(() => {
  vi.useRealTimers();
});

// With JS_COVERAGE=1 the scripts are instrumented (config/js_coverage.ts); each
// test file's counters go to tmp/js-coverage/unit-<pid>-<random>.json, beside
// the browser counters, for nyc to merge.
if (process.env.JS_COVERAGE === "1") {
  afterAll(() => {
    if (!globalThis.__coverage__) return;
    const dir = join(process.cwd(), "tmp", "js-coverage");
    mkdirSync(dir, { recursive: true });
    const name = `unit-${process.pid}-${randomBytes(4).toString("hex")}.json`;
    writeFileSync(join(dir, name), JSON.stringify(globalThis.__coverage__));
  });
}
